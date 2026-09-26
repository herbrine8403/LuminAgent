#ifndef LA_CHAT_VC_H
#define LA_CHAT_VC_H

/* 聊天界面：用户气泡（L2 + accent 染色）/ AI 气泡（Surface 色）+
 * caption1 时间戳 + 26pt 头像容器 + ToolCallCard + PermissionCard +
 * 输入框焦点 1→2pt 动画。只消费 Session/Tools 契约。 */

#import <UIKit/UIKit.h>

@class LAMessage;
@class LAChatVC;

@protocol LAChatDelegate <NSObject>
@optional
- (void)chatVC:(LAChatVC *)vc didSendText:(NSString *)text;
@end

/* 工具调用卡：工具名 + 参数摘要 + 状态 pill */
@interface ToolCallCardView : UIView
- (void)configureWithTool:(NSString *)tool arguments:(nullable NSString *)args status:(NSString *)status;
@end

/* 权限确认卡：工具/目标/原因 + 允许/拒绝，回传统一 LAPermissionDecision */
@interface PermissionCardView : UIView
- (void)configureWithTool:(NSString *)tool
                   target:(nullable NSString *)target
                   reason:(nullable NSString *)reason
              completion:(void (^)(NSInteger decision))completion;
@end

@interface LAChatVC : UIViewController

@property (nonatomic, weak) id<LAChatDelegate> delegate;

/* 消息流刷新（LAMessage 数组） */
- (void)reloadWithMessages:(NSArray<LAMessage *> *)messages;

@end

#endif /* LA_CHAT_VC_H */
