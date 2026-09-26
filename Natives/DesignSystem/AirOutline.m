#import "AirOutline.h"

/* 边框语义实现：深浅自适应 */

@implementation AirOutline

+ (UIColor *)outlineColor {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        if (traits.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [[UIColor whiteColor] colorWithAlphaComponent:0.20];
        }
        return [[UIColor blackColor] colorWithAlphaComponent:0.12];
    }];
}

+ (UIColor *)variantColor {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        if (traits.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [[UIColor whiteColor] colorWithAlphaComponent:0.10];
        }
        return [[UIColor blackColor] colorWithAlphaComponent:0.06];
    }];
}

@end
