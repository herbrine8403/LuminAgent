#ifndef AIR_FILTER_CHIP_PANEL_H
#define AIR_FILTER_CHIP_PANEL_H

/* FilterChipPanel：横向单选 chip 条（对齐 SKILL §7.1）。
 * chip 高 28 / 圆角 14 / 选中染色，未选中描边 variant。 */

#import <UIKit/UIKit.h>

@class FilterChipPanel;

@protocol FilterChipPanelDelegate <NSObject>
@optional
- (void)chipPanel:(FilterChipPanel *)panel didSelectIndex:(NSInteger)index;
@end

@interface FilterChipPanel : UIView

@property (nonatomic, weak) id<FilterChipPanelDelegate> delegate;
@property (nonatomic, assign, readonly) NSInteger selectedIndex;

/* 标题组 + 默认选中（-1=无选中），重建全部 chip */
- (void)setTitles:(NSArray<NSString *> *)titles selectedIndex:(NSInteger)index;

/* 程序化选中（含选中样式刷新与 delegate 回调可选） */
- (void)selectIndex:(NSInteger)index notify:(BOOL)notify;

@end

#endif /* AIR_FILTER_CHIP_PANEL_H */
