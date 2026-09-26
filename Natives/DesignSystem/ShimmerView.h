#ifndef AIR_SHIMMER_VIEW_H
#define AIR_SHIMMER_VIEW_H

/* Shimmer 骨架块：加载态骨架屏原子，opacity 动画由 AirAnimation 驱动 */

#import <UIKit/UIKit.h>

@interface ShimmerView : UIView

/* 以圆角创建骨架块（默认 AirRadiusSM=8，continuous） */
- (instancetype)initWithCornerRadius:(CGFloat)radius;

/* 开始/停止骨架闪烁 */
- (void)startShimmering;
- (void)stopShimmering;

@end

#endif /* AIR_SHIMMER_VIEW_H */
