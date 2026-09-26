#import "ShimmerView.h"
#import "AirSurface.h"
#import "AirAnimation.h"

/* 骨架块实现：item 色底 + continuous 圆角 */

@implementation ShimmerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInitWithRadius:AirRadiusSM];
    }
    return self;
}

- (instancetype)initWithCornerRadius:(CGFloat)radius {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        [self commonInitWithRadius:radius];
    }
    return self;
}

/* 公共初始化：底色 + 圆角 + 无障碍标记为装饰 */
- (void)commonInitWithRadius:(CGFloat)radius {
    self.backgroundColor = [AirSurface itemColor];
    self.layer.cornerRadius = radius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
    self.isAccessibilityElement = NO;
}

- (void)startShimmering {
    [AirAnimation startShimmerOnView:self];
}

- (void)stopShimmering {
    [AirAnimation stopShimmerOnView:self];
}

@end
