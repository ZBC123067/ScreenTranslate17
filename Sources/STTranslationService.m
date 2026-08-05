#import "STTranslationService.h"
#import "STPreferences.h"
#import "STCache.h"
#import "STPrivacy.h"
#import "STCommon.h"

typedef void (^STProviderCompletion)(NSString *_Nullable translatedText, NSError *_Nullable error);

@interface STTranslationService ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSOperationQueue *requestQueue;
@property (nonatomic, strong) dispatch_queue_t stateQueue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *inFlight;
@end

@implementation STTranslationService

+ (instancetype)shared {
    static STTranslationService *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [STTranslationService new]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.timeoutIntervalForRequest = 18.0;
        configuration.timeoutIntervalForResource = 30.0;
        configuration.HTTPMaximumConnectionsPerHost = 2;
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        _session = [NSURLSession sessionWithConfiguration:configuration];
        _requestQueue = [NSOperationQueue new];
        _requestQueue.name = @"com.wmm.screentranslate17.translation";
        _requestQueue.maxConcurrentOperationCount = 2;
        _stateQueue = dispatch_queue_create("com.wmm.screentranslate17.translation.state", DISPATCH_QUEUE_SERIAL);
        _inFlight = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)translateText:(NSString *)text completion:(STTranslationCompletion)completion {
    STPreferences *preferences = STPreferences.shared;
    [self translateText:text source:preferences.sourceLanguage target:preferences.targetLanguage completion:completion];
}

- (NSString *)requestKeyForText:(NSString *)text source:(NSString *)source target:(NSString *)target provider:(NSString *)provider {
    return STSHA256([NSString stringWithFormat:@"%@\n%@\n%@\n%@", provider ?: @"", source ?: @"", target ?: @"", text ?: @""]);
}

- (void)completeRequest:(NSString *)requestKey translation:(NSString *)translation error:(NSError *)error cacheText:(NSString *)cacheText source:(NSString *)source target:(NSString *)target provider:(NSString *)provider shouldCache:(BOOL)shouldCache {
    if (translation.length && shouldCache) [[STCache shared] storeTranslation:translation forText:cacheText source:source target:target provider:provider];
    dispatch_async(self.stateQueue, ^{
        NSArray *completions = [self.inFlight[requestKey] copy] ?: @[];
        [self.inFlight removeObjectForKey:requestKey];
        STDispatchMain(^{
            for (STTranslationCompletion completion in completions) completion(translation, error);
        });
    });
}

- (void)translateText:(NSString *)text source:(NSString *)source target:(NSString *)target completion:(STTranslationCompletion)completion {
    [self translateText:text source:source target:target bypassCache:NO eligibility:nil completion:completion];
}

- (BOOL)isEligibleForNetwork:(STTranslationEligibility)eligibility {
    if (!eligibility) return YES;
    __block BOOL eligible = NO;
    void (^check)(void) = ^{ eligible = eligibility(); };
    if (NSThread.isMainThread) check();
    else dispatch_sync(dispatch_get_main_queue(), check);
    return eligible;
}

- (void)translateText:(NSString *)text source:(NSString *)source target:(NSString *)target bypassCache:(BOOL)bypassCache eligibility:(STTranslationEligibility)eligibility completion:(STTranslationCompletion)completion {
    NSString *normalized = STNormalizeText(text);
    source = source.length ? source : @"auto";
    target = target.length ? target : @"zh-CN";
    if (!STLooksLikeTranslatableText(normalized, target)) {
        STDispatchMain(^{ if (completion) completion(nil, STMakeError(1, @"没有可翻译的文本，或文本长度超出限制。")); });
        return;
    }

    NSString *offline = [STPrivacy offlineGlossaryTranslationForText:normalized targetLanguage:target];
    if (offline.length) {
        STDispatchMain(^{ if (completion) completion(offline, nil); });
        return;
    }

    STPreferences *preferences = STPreferences.shared;
    NSString *provider = preferences.provider.lowercaseString;
    if (![provider isEqualToString:@"openai_compatible"] && ![provider isEqualToString:@"deepl"] && ![provider isEqualToString:@"microsoft"]) {
        STDispatchMain(^{ if (completion) completion(nil, STMakeError(2, @"请选择并配置受支持的翻译服务。Google Web 实验接口已禁用。")); });
        return;
    }
    STPreparedText *prepared = [STPrivacy prepareTextForNetwork:normalized];
    BOOL shouldCache = !bypassCache && prepared.tokens.count == 0 && ![STPrivacy textContainsSensitiveData:normalized];
    if (shouldCache) {
        NSString *cached = [[STCache shared] translationForText:normalized source:source target:target provider:provider];
        if (cached.length) {
            STDispatchMain(^{ if (completion) completion(cached, nil); });
            return;
        }
    }
    if (!preferences.allowNetwork) {
        STDispatchMain(^{ if (completion) completion(nil, STMakeError(3, @"联网翻译已关闭，且没有可用的本地缓存。")); });
        return;
    }
    if (![self isEligibleForNetwork:eligibility]) {
        STDispatchMain(^{ if (completion) completion(nil, STMakeError(6, @"当前页面已切换或包含敏感内容，已取消联网翻译。")); });
        return;
    }

    NSString *requestText = prepared.text;
    NSString *requestKey = [self requestKeyForText:(shouldCache ? requestText : [requestText stringByAppendingString:[[NSUUID UUID] UUIDString]]) source:source target:target provider:provider];
    __block BOOL shouldStart = NO;
    dispatch_sync(self.stateQueue, ^{
        NSMutableArray *existing = self.inFlight[requestKey];
        if (existing) {
            if (completion) [existing addObject:[completion copy]];
        } else {
            self.inFlight[requestKey] = completion ? [NSMutableArray arrayWithObject:[completion copy]] : [NSMutableArray array];
            shouldStart = YES;
        }
    });
    if (!shouldStart) return;

    __weak typeof(self) weakSelf = self;
    [self.requestQueue addOperationWithBlock:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        __block BOOL finished = NO;
        void (^finish)(NSString *, NSError *) = ^(NSString *translated, NSError *error) {
            @synchronized (self) {
                if (finished) return;
                finished = YES;
            }
            NSString *restored = translated.length ? [STPrivacy restoreTokensInText:translated tokens:prepared.tokens] : nil;
            [self completeRequest:requestKey translation:restored error:error cacheText:normalized source:source target:target provider:provider shouldCache:shouldCache];
            dispatch_semaphore_signal(semaphore);
        };
        if (![self isEligibleForNetwork:eligibility]) {
            finish(nil, STMakeError(6, @"当前页面已切换或包含敏感内容，已取消联网翻译。"));
            return;
        }
        if ([provider isEqualToString:@"openai_compatible"]) [self translateWithOpenAI:requestText source:source target:target completion:finish];
        else if ([provider isEqualToString:@"deepl"]) [self translateWithDeepL:requestText source:source target:target completion:finish];
        else [self translateWithMicrosoft:requestText source:source target:target completion:finish];
        if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(35 * NSEC_PER_SEC))) != 0) {
            finish(nil, STMakeError(4, @"翻译请求超时。"));
        }
    }];
}

- (NSURL *)validatedHTTPSURL:(NSString *)string error:(NSError **)error {
    NSURLComponents *components = [NSURLComponents componentsWithString:string];
    if (!components.URL || ![components.scheme.lowercaseString isEqualToString:@"https"] || !components.host.length) {
        if (error) *error = STMakeError(5, @"API 地址必须是有效的 HTTPS 地址。");
        return nil;
    }
    return components.URL;
}

- (NSError *)HTTPErrorForResponse:(NSURLResponse *)response data:(NSData *)data fallback:(NSString *)fallback {
    NSInteger status = [(NSHTTPURLResponse *)response statusCode];
    if (status >= 200 && status < 300) return nil;
    NSString *message;
    if (data.length) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        id errorObject = [json isKindOfClass:NSDictionary.class] ? json[@"error"] : nil;
        if ([errorObject isKindOfClass:NSDictionary.class]) message = errorObject[@"message"];
        else if ([errorObject isKindOfClass:NSString.class]) message = errorObject;
    }
    return STMakeError(100 + status, message.length ? message : [NSString stringWithFormat:@"%@（HTTP %ld）", fallback, (long)status]);
}

- (void)translateWithOpenAI:(NSString *)text source:(NSString *)source target:(NSString *)target completion:(STProviderCompletion)completion {
    STPreferences *preferences = STPreferences.shared;
    if (!preferences.apiKey.length) { completion(nil, STMakeError(20, @"尚未填写 OpenAI 兼容服务的 API Key。")); return; }
    NSError *urlError;
    NSURL *url = [self validatedHTTPSURL:(preferences.apiEndpoint.length ? preferences.apiEndpoint : @"https://api.openai.com/v1/chat/completions") error:&urlError];
    if (!url) { completion(nil, urlError); return; }
    NSString *system = [NSString stringWithFormat:@"You are a precise translation engine. Translate from %@ to %@. Preserve names, vessel/voyage, ports, dates, currencies, formatting, and any placeholders beginning with [[ST_PRIVATE_]] exactly, including all punctuation and capitalization. Return only the translation. %@", source, target, [STPrivacy shippingGlossaryInstructionForTargetLanguage:target]];
    NSDictionary *body = @{
        @"model": preferences.apiModel.length ? preferences.apiModel : @"gpt-4.1-mini",
        @"temperature": @0,
        @"messages": @[ @{ @"role": @"system", @"content": system }, @{ @"role": @"user", @"content": text } ]
    };
    NSError *jsonError;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    if (!bodyData) { completion(nil, jsonError ?: STMakeError(21, @"无法编码翻译请求。")); return; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = bodyData;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[@"Bearer " stringByAppendingString:preferences.apiKey] forHTTPHeaderField:@"Authorization"];
    [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSError *httpError = [self HTTPErrorForResponse:response data:data fallback:@"OpenAI 兼容服务请求失败"];
        if (httpError) { completion(nil, httpError); return; }
        NSError *parseError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        NSArray *choices = [json isKindOfClass:NSDictionary.class] ? json[@"choices"] : nil;
        NSDictionary *message = ([choices isKindOfClass:NSArray.class] && choices.count && [choices.firstObject isKindOfClass:NSDictionary.class]) ? choices.firstObject[@"message"] : nil;
        NSString *result = [message isKindOfClass:NSDictionary.class] ? message[@"content"] : nil;
        result = STNormalizeText(result);
        completion(result.length ? result : nil, result.length ? nil : (parseError ?: STMakeError(22, @"服务未返回有效译文。")));
    }] resume];
}

- (NSString *)deepLCanonicalLanguage:(NSString *)language target:(BOOL)target {
    NSString *lower = language.lowercaseString;
    NSDictionary<NSString *, NSString *> *aliases = @{
        @"zh": @"ZH", @"zh-cn": @"ZH", @"zh-hans": @"ZH",
        @"en": target ? @"EN-US" : @"EN", @"en-us": @"EN-US", @"en-gb": @"EN-GB",
        @"pt": target ? @"PT-PT" : @"PT", @"pt-br": @"PT-BR", @"pt-pt": @"PT-PT",
        @"no": @"NB", @"nb-no": @"NB", @"id-id": @"ID", @"ja-jp": @"JA", @"ko-kr": @"KO",
        @"vi-vn": @"VI", @"th-th": @"TH", @"tr-tr": @"TR", @"uk-ua": @"UK"
    };
    NSString *canonical = aliases[lower] ?: language.uppercaseString;
    NSSet<NSString *> *sourceLanguages = [NSSet setWithArray:@[ @"AR", @"BG", @"CS", @"DA", @"DE", @"EL", @"EN", @"ES", @"ET", @"FI", @"FR", @"HU", @"ID", @"IT", @"JA", @"KO", @"LT", @"LV", @"NB", @"NL", @"PL", @"PT", @"RO", @"RU", @"SK", @"SL", @"SV", @"TR", @"UK", @"VI", @"ZH" ]];
    NSSet<NSString *> *targetLanguages = [NSSet setWithArray:@[ @"AR", @"BG", @"CS", @"DA", @"DE", @"EL", @"EN-GB", @"EN-US", @"ES", @"ET", @"FI", @"FR", @"HU", @"ID", @"IT", @"JA", @"KO", @"LT", @"LV", @"NB", @"NL", @"PL", @"PT-BR", @"PT-PT", @"RO", @"RU", @"SK", @"SL", @"SV", @"TR", @"UK", @"VI", @"ZH" ]];
    return [(target ? targetLanguages : sourceLanguages) containsObject:canonical] ? canonical : nil;
}

- (void)translateWithDeepL:(NSString *)text source:(NSString *)source target:(NSString *)target completion:(STProviderCompletion)completion {
    STPreferences *preferences = STPreferences.shared;
    if (!preferences.apiKey.length) { completion(nil, STMakeError(30, @"尚未填写 DeepL API Key。")); return; }
    NSError *urlError;
    NSURL *url = [self validatedHTTPSURL:(preferences.apiEndpoint.length ? preferences.apiEndpoint : @"https://api-free.deepl.com/v2/translate") error:&urlError];
    if (!url) { completion(nil, urlError); return; }
    NSString *targetLanguage = [self deepLCanonicalLanguage:target target:YES];
    if (!targetLanguage.length) { completion(nil, STMakeError(32, @"DeepL 不支持当前目标语言；请改用其支持的目标语言代码。")); return; }
    NSMutableDictionary *body = [@{ @"text": @[ text ], @"target_lang": targetLanguage } mutableCopy];
    if (source.length && ![source.lowercaseString isEqualToString:@"auto"]) {
        NSString *sourceLanguage = [self deepLCanonicalLanguage:source target:NO];
        if (!sourceLanguage.length) { completion(nil, STMakeError(33, @"DeepL 不支持当前源语言；请使用 auto 或其支持的源语言代码。")); return; }
        body[@"source_lang"] = sourceLanguage;
    }
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = bodyData;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[@"DeepL-Auth-Key " stringByAppendingString:preferences.apiKey] forHTTPHeaderField:@"Authorization"];
    [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSError *httpError = [self HTTPErrorForResponse:response data:data fallback:@"DeepL 请求失败"];
        if (httpError) { completion(nil, httpError); return; }
        NSError *parseError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        NSArray *translations = [json isKindOfClass:NSDictionary.class] ? json[@"translations"] : nil;
        NSDictionary *first = ([translations isKindOfClass:NSArray.class] && translations.count && [translations.firstObject isKindOfClass:NSDictionary.class]) ? translations.firstObject : nil;
        NSString *result = STNormalizeText(first[@"text"]);
        completion(result.length ? result : nil, result.length ? nil : (parseError ?: STMakeError(31, @"DeepL 未返回有效译文。")));
    }] resume];
}

- (NSString *)microsoftLanguage:(NSString *)language {
    NSString *lower = language.lowercaseString;
    if ([lower hasPrefix:@"zh-cn"] || [lower isEqualToString:@"zh"]) return @"zh-Hans";
    if ([lower hasPrefix:@"zh-tw"]) return @"zh-Hant";
    return language;
}

- (void)translateWithMicrosoft:(NSString *)text source:(NSString *)source target:(NSString *)target completion:(STProviderCompletion)completion {
    STPreferences *preferences = STPreferences.shared;
    if (!preferences.apiKey.length) { completion(nil, STMakeError(40, @"尚未填写 Microsoft Translator Key。")); return; }
    NSURLComponents *components = [NSURLComponents componentsWithString:(preferences.apiEndpoint.length ? preferences.apiEndpoint : @"https://api.cognitive.microsofttranslator.com/translate")];
    NSError *urlError;
    if (![self validatedHTTPSURL:components.string error:&urlError]) { completion(nil, urlError); return; }
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray arrayWithArray:components.queryItems ?: @[]];
    [items addObject:[NSURLQueryItem queryItemWithName:@"api-version" value:@"3.0"]];
    [items addObject:[NSURLQueryItem queryItemWithName:@"to" value:[self microsoftLanguage:target]]];
    if (source.length && ![source.lowercaseString isEqualToString:@"auto"]) [items addObject:[NSURLQueryItem queryItemWithName:@"from" value:[self microsoftLanguage:source]];
    components.queryItems = items;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:components.URL];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@[ @{ @"Text": text } ] options:0 error:nil];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:preferences.apiKey forHTTPHeaderField:@"Ocp-Apim-Subscription-Key"];
    if (preferences.apiRegion.length) [request setValue:preferences.apiRegion forHTTPHeaderField:@"Ocp-Apim-Subscription-Region"];
    [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSError *httpError = [self HTTPErrorForResponse:response data:data fallback:@"Microsoft Translator 请求失败"];
        if (httpError) { completion(nil, httpError); return; }
        NSError *parseError;
        NSArray *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        NSDictionary *first = ([json isKindOfClass:NSArray.class] && json.count && [json.firstObject isKindOfClass:NSDictionary.class]) ? json.firstObject : nil;
        NSArray *translations = [first isKindOfClass:NSDictionary.class] ? first[@"translations"] : nil;
        NSDictionary *translation = ([translations isKindOfClass:NSArray.class] && translations.count && [translations.firstObject isKindOfClass:NSDictionary.class]) ? translations.firstObject : nil;
        NSString *result = STNormalizeText(translation[@"text"]);
        completion(result.length ? result : nil, result.length ? nil : (parseError ?: STMakeError(41, @"Microsoft Translator 未返回有效译文。")));
    }] resume];
}
@end
