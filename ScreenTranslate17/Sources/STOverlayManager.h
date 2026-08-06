#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "STCommon.h"

NS_ASSUME_NONNULL_BEGIN

@class STOverlayManager;
@protocol STOverlayManagerDelegate <NSObject>
- (void)overlayManagerDidRequestScreenTranslation:(STOverlayManager *)manager;
- (void)overlayManagerDidRequestOCRTranslation:(STOverlayManager *)manager;
- (void)overlayManagerDidRequestRegionTranslation:(STOverlayManager *)manager;
- (void)overlayManagerDidRequestToggleContinuous:(STOverlayManager *)manager;
- (void)overlayManagerDidRequestInputTranslation:(STOverlayManager *)manager;
- (void)overlayManagerDidRequestToggleChatMode:(STOverlayManager *)manager;
@end

@interface STOverlayManager : NSObject
@property (nonatomic, weak) id<STOverlayManagerDelegate> delegate;
@property (nonatomic, readonly) BOOL translationsHidden;
- (void)installIfNeeded;
- (void)setBallVisible:(BOOL)visible;
- (void)setBusy:(BOOL)busy;
- (void)setStatusColor:(UIColor *)color;
- (void)showStatus:(NSString *)message busy:(BOOL)busy autoHideAfter:(NSTimeInterval)delay;
- (void)updateModeStateContinuous:(BOOL)continuousActive chatActive:(BOOL)chatActive;
- (void)showTranslation:(NSString *)translation forItem:(STTextItem *)item;
- (void)showSubtitle:(NSString *)translation original:(nullable NSString *)original;
- (void)clearTranslations;
- (void)toggleTranslations;
- (void)showMessage:(NSString *)message;
- (void)presentControlPanelWithContinuousActive:(BOOL)continuousActive chatActive:(BOOL)chatActive;
- (void)presentInputReplacementConfirmation:(NSString *)translation completion:(void (^)(BOOL replace))completion;
- (void)refreshForCurrentScene;
- (UIView *)overlayRootView;
@end

NS_ASSUME_NONNULL_END
