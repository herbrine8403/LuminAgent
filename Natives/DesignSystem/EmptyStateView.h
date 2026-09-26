#ifndef AIR_EMPTY_STATE_VIEW_H
#define AIR_EMPTY_STATE_VIEW_H

/* EmptyStateView：列表三态（对齐 SKILL §10）—
 * 空（图标+文案+引导按钮）/ 加载（Shimmer 骨架）/ 错误（InlineMessage 风格+重试）。 */

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, AirEmptyStateKind) {
    AirEmptyStateKindEmpty = 0,   /* 空：图标 + 文案 + 引导操作 */
    AirEmptyStateKindLoading = 1, /* 加载：Shimmer 骨架屏 */
    AirEmptyStateKindError = 2,   /* 错误：InlineMessage 风格 + 重试 */
};

@interface EmptyStateView : UIView

/* 空态：图标名（SF Symbol）+ 标题 + 引导按钮（actionTitle 为空则隐藏按钮） */
- (void)showEmptyWithIcon:(NSString *)symbolName
                    title:(NSString *)title
              actionTitle:(nullable NSString *)actionTitle
                   target:(nullable id)target
                   action:(nullable SEL)action;

/* 加载态：三行 Shimmer 骨架 + 可选副标题 */
- (void)showLoadingWithTitle:(nullable NSString *)title;

/* 错误态：InlineMessage 风格错误卡 + 重试按钮 */
- (void)showErrorWithTitle:(NSString *)title
               retryTitle:(NSString *)retryTitle
                   target:(nullable id)target
                   action:(nullable SEL)action;

/* 隐藏（三态互斥，调任一 show 即切换） */
- (void)dismiss;

@end

#endif /* AIR_EMPTY_STATE_VIEW_H */
