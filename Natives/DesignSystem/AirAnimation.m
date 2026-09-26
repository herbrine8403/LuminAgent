#import "AirAnimation.h"

/* 动效实现：四缓动 + 连锁 + Shimmer + 主题遮罩 */

static NSString *const kAirShimmerKey = @"air.shimmer";
static NSString *const kAirThemeMaskKey = @"air.themeMask";

@implementation AirAnimation

+ (AirTransitionAnimationType)currentType {
    NSInteger raw = [[NSUserDefaults standardUserDefaults] integerForKey:@"general.transition_animation_type"];
    if (raw < AirTransitionAnimationClose || raw > AirTransitionAnimationSliceIn) {
        return AirTransitionAnimationJellyBounce;
    }
    return (AirTransitionAnimationType)raw;
}

+ (NSTimeInterval)durationForType:(AirTransitionAnimationType)type {
    switch (type) {
        case AirTransitionAnimationClose: return 0;
        case AirTransitionAnimationJellyBounce: return 0.6;
        case AirTransitionAnimationBounce: return 0.5;
        case AirTransitionAnimationSliceIn: return 0.4;
    }
}

+ (UIViewAnimationOptions)optionsForType:(AirTransitionAnimationType)type {
    switch (type) {
        case AirTransitionAnimationClose: return 0;
        case AirTransitionAnimationJellyBounce:
            return UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction;
        case AirTransitionAnimationBounce: return UIViewAnimationOptionCurveEaseInOut;
        case AirTransitionAnimationSliceIn: return UIViewAnimationOptionCurveEaseOut;
    }
}

+ (void)animateItemsInChain:(NSArray<UIView *> *)items {
    NSUInteger capped = MIN(items.count, 10); /* 上限 10，超限同时进场 */
    for (NSUInteger i = 0; i < capped; i++) {
        UIView *item = items[i];
        CGAffineTransform original = item.transform;
        item.transform = CGAffineTransformTranslate(original, 0, -40);
        item.alpha = 0;
        [UIView animateWithDuration:0.5
                              delay:i * 0.05 /* 50ms 递增 */
             usingSpringWithDamping:0.85
              initialSpringVelocity:0.4
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            item.transform = original;
            item.alpha = 1;
        } completion:nil];
    }
}

+ (CAKeyframeAnimation *)jellyBounceAnimation {
    CAKeyframeAnimation *anim = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    anim.duration = 0.6;
    anim.values = @[@0.95, @1.08, @0.96, @1.03, @1.0];
    anim.keyTimes = @[@0, @0.3, @0.5, @0.75, @1];
    anim.timingFunctions = @[
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn]
    ];
    return anim;
}

+ (void)pressDownView:(UIView *)view {
    [UIView animateWithDuration:0.25 delay:0
         usingSpringWithDamping:0.7 initialSpringVelocity:0.8
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        view.transform = CGAffineTransformMakeScale(0.96, 0.96);
    } completion:nil];
}

+ (void)releaseView:(UIView *)view {
    [UIView animateWithDuration:0.25 delay:0
         usingSpringWithDamping:0.7 initialSpringVelocity:0.8
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        view.transform = CGAffineTransformIdentity;
    } completion:nil];
}

+ (void)startShimmerOnView:(UIView *)view {
    [view.layer removeAnimationForKey:kAirShimmerKey];
    CABasicAnimation *shimmer = [CABasicAnimation animationWithKeyPath:@"opacity"];
    shimmer.fromValue = @0.3;
    shimmer.toValue = @0.6;
    shimmer.duration = 1.0;
    shimmer.repeatCount = INFINITY;
    shimmer.autoreverses = YES;
    shimmer.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [view.layer addAnimation:shimmer forKey:kAirShimmerKey];
}

+ (void)stopShimmerOnView:(UIView *)view {
    [view.layer removeAnimationForKey:kAirShimmerKey];
    view.alpha = 1.0;
}

+ (void)switchThemeWithMaskInView:(UIView *)container
                       fromPoint:(CGPoint)point
                      applyBlock:(void (^)(void))applyBlock {
    UIView *snapshot = [container snapshotViewAfterScreenUpdates:NO];
    if (!snapshot) {
        if (applyBlock) { applyBlock(); }
        return;
    }
    snapshot.frame = container.bounds;
    snapshot.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [container addSubview:snapshot];

    CAShapeLayer *maskLayer = [CAShapeLayer layer];
    maskLayer.frame = snapshot.bounds;
    CGFloat maxRadius = sqrt(pow(container.bounds.size.width, 2) + pow(container.bounds.size.height, 2));
    UIBezierPath *startPath = [UIBezierPath bezierPathWithArcCenter:point radius:1
                                                         startAngle:0 endAngle:2 * M_PI clockwise:YES];
    UIBezierPath *endPath = [UIBezierPath bezierPathWithArcCenter:point radius:maxRadius
                                                       startAngle:0 endAngle:2 * M_PI clockwise:YES];
    maskLayer.path = endPath.CGPath;
    snapshot.layer.mask = maskLayer;

    CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"path"];
    anim.duration = 0.8; /* 800ms */
    anim.fromValue = (__bridge id)startPath.CGPath;
    anim.toValue = (__bridge id)endPath.CGPath;
    anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    anim.removedOnCompletion = NO;
    anim.fillMode = kCAFillModeForwards;
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        [snapshot removeFromSuperview];
    }];
    /* 动画 50% 处（400ms）切换主题 */
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (applyBlock) { applyBlock(); }
    });
    [maskLayer addAnimation:anim forKey:kAirThemeMaskKey];
    [CATransaction commit];
}

@end
