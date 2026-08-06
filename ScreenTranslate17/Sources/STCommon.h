#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const STPreferencesChangedDarwinNotification;
FOUNDATION_EXPORT NSString * const STPreferenceDomain;

FOUNDATION_EXPORT NSString *STJBRootPath(NSString *relativePath);
FOUNDATION_EXPORT UIWindow *_Nullable STActiveAppWindow(void);
FOUNDATION_EXPORT UIViewController *_Nullable STTopViewController(void);
FOUNDATION_EXPORT NSString *STNormalizeText(NSString *_Nullable text);
FOUNDATION_EXPORT BOOL STContainsCJK(NSString *text);
FOUNDATION_EXPORT BOOL STLooksLikeTranslatableText(NSString *text, NSString *targetLanguage);
FOUNDATION_EXPORT NSString *STSHA256(NSString *string);
FOUNDATION_EXPORT NSError *STMakeError(NSInteger code, NSString *message);
FOUNDATION_EXPORT void STDispatchMain(dispatch_block_t block);

@interface STTextItem : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) CGRect frame;
@property (nonatomic, weak, nullable) UIView *sourceView;
@property (nonatomic, assign) BOOL fromOCR;
+ (instancetype)itemWithText:(NSString *)text frame:(CGRect)frame sourceView:(UIView *_Nullable)view;
@end

NS_ASSUME_NONNULL_END
