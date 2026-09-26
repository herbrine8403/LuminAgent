#ifndef VM_TILE_BASE_CELL_H
#define VM_TILE_BASE_CELL_H

/* Bento 磁贴基类：中阴影 + 12pt continuous 圆角 + 毛玻璃位 +
 * 按压弹簧 + 选中三层（1.5pt accent 边框 + 徽章 + 染色）+ 禁用 0.38。
 * 可点 Cell 必带 chevron.right（tertiary）。 */

#import <UIKit/UIKit.h>

@interface VMTileBaseCell : UICollectionViewCell

/* 图标容器（类型语义色底，10pt 圆角）+ 22pt 本体 */
@property (nonatomic, strong, readonly) UIView *iconContainer;
@property (nonatomic, strong, readonly) UIImageView *iconView;
/* 标题（title3）+ 副标题（caption1） */
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UILabel *subtitleLabel;
/* 右侧 chevron（可点时显示，tertiary） */
@property (nonatomic, strong, readonly) UIImageView *chevronView;
/* 右上角选中徽章（accent 圆点 + 白色 checkmark） */
@property (nonatomic, strong, readonly) UIView *selectedBadge;

/* 选中态三层强化（边框 1.5pt accent + 徽章 + 背景染色） */
- (void)setSelectedState:(BOOL)selected;

/* 禁用态（整体 alpha 0.38） */
- (void)setDisabled:(BOOL)disabled;

/* 可点暗示：YES 显示 chevron，NO 隐藏 */
- (void)setTappable:(BOOL)tappable;

/* 紧凑磁贴关闭 Dynamic Type 自适应（维持布局稳定） */
- (void)setCompactAdaptive:(BOOL)compact;

@end

#endif /* VM_TILE_BASE_CELL_H */
