#ifndef LA_TRAJECTORY_VC_H
#define LA_TRAJECTORY_VC_H

/* 轨迹审计：事件流列表 + 来源插件彩色标注 + 类型 chip 过滤。
 * 只消费 LATrajectoryStore 契约（事件类型↔字符串经 store 工具）。 */

#import <UIKit/UIKit.h>

@class LATrajectoryStore;

@interface LATrajectoryVC : UIViewController

- (instancetype)initWithStore:(LATrajectoryStore *)store;

/* 流刷新（全量重读 eventsSinceSeq:0） */
- (void)reload;

@end

#endif /* LA_TRAJECTORY_VC_H */
