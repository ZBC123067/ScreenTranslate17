#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^STRegionSelectionCompletion)(CGRect region, BOOL cancelled);

@interface STRegionSelector : NSObject
- (void)presentInView:(UIView *)view completion:(STRegionSelectionCompletion)completion;
@end

NS_ASSUME_NONNULL_END
