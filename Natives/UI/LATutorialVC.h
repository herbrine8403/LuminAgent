#ifndef LA_TUTORIAL_VC_H
#define LA_TUTORIAL_VC_H

/* 新手教程页：4 页横滑（会话/模型/Skills/权限）+ 跳过/开始，
 * 首启经 EngineLauncher 模态展示一次，关闭后写 NSUserDefaults 标记。 */

#import <UIKit/UIKit.h>

@interface LATutorialVC : UIViewController

/* 关闭回调（跳过与开始均触发，由协调器写已读标记并 dismiss） */
@property (nonatomic, copy, nullable) void (^completion)(void);

@end

#endif /* LA_TUTORIAL_VC_H */
