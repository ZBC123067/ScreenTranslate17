#import <Foundation/Foundation.h>
#import "STOverlayManager.h"

NS_ASSUME_NONNULL_BEGIN
@interface STManager : NSObject <STOverlayManagerDelegate>
+ (instancetype)sharedManager;
- (void)scheduleStart;
@end
NS_ASSUME_NONNULL_END
