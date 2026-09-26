#ifndef AIR_ANIMATION_H
#define AIR_ANIMATION_H

/* 动效主场（对齐 SKILL §15.1/15.3/15.4/15.5/15.10）：
 * 四种缓动（Close/JellyBounce 默认/Bounce/SliceIn）+ 连锁进场 +
 * Shimmer 骨架 + 主题遮罩。禁止自创第五种缓动。 */

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, AirTransitionAnimationType) {
    AirTransitionAnimationClose = 0,       /* 无动画（snap） */
    AirTransitionAnimationJellyBounce = 1, /* 果冻回弹（默认） */
    AirTransitionAnimationBounce = 2,      /* 标准弹跳 */
    AirTransitionAnimationSliceIn = 3,     /* 平滑切入 */
};

@interface AirAnimation : NSObject

/* 当前偏好类型（general.transition_animation_type，缺省 JellyBounce） */
+ (AirTransitionAnimationType)currentType;

/* 各类型时长：Close 0 / JellyBounce 0.6 / Bounce 0.5 / SliceIn 0.4 */
+ (NSTimeInterval)durationForType:(AirTransitionAnimationType)type;

/* 各类型 options：Close 0 / JellyBounce 允许用户交互曲线 / Bounce EaseInOut / SliceIn EaseOut */
+ (UIViewAnimationOptions)optionsForType:(AirTransitionAnimationType)type;

/* 连锁进场：每项延迟 50ms，上方 -40pt 滑入 + 淡入，上限 10 个 */
+ (void)animateItemsInChain:(NSArray<UIView *> *)items;

/* JellyBounce 关键帧（阻尼余弦 f(t)=1-0.6*exp(-8t)*cos(6πt)，3 周期） */
+ (CAKeyframeAnimation *)jellyBounceAnimation;

/* 按压弹簧：压下 0.96 / 回弹 identity（阻尼 0.7，初速 0.8） */
+ (void)pressDownView:(UIView *)view;
+ (void)releaseView:(UIView *)view;

/* Shimmer 骨架：opacity 0.3↔0.6，1.0s 线性往返无限 */
+ (void)startShimmerOnView:(UIView *)view;
+ (void)stopShimmerOnView:(UIView *)view;

/* 主题切换遮罩：截图 → 从触摸点/中心圆形扩散 → 400ms 处换肤，全程 800ms */
+ (void)switchThemeWithMaskInView:(UIView *)container
                       fromPoint:(CGPoint)point
                      applyBlock:(void (^)(void))applyBlock;

@end

#endif /* AIR_ANIMATION_H */
