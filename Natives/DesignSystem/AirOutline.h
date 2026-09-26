#ifndef AIR_OUTLINE_H
#define AIR_OUTLINE_H

/* 边框语义（对齐 SKILL §2.8）：outline 强调边框，variant 弱化边框 */

#import <UIKit/UIKit.h>

@interface AirOutline : NSObject

/* 强调边框：输入框未聚焦、分隔线（深色白 0.20 / 浅色黑 0.12） */
+ (UIColor *)outlineColor;

/* 弱化边框：卡片默认描边、chip 未选中描边（深色白 0.10 / 浅色黑 0.06） */
+ (UIColor *)variantColor;

@end

#endif /* AIR_OUTLINE_H */
