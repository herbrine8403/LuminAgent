#import "AirSurface.h"
#import "AirOutline.h"

/* 设计令牌实现：深浅自适应经 dynamicProvider，alpha 全部收敛于此 */

UIColor *LAAcentColor(void) {
    NSString *hex = [[NSUserDefaults standardUserDefaults] stringForKey:@"general.accent_color"];
    unsigned int rgb = 0x429CF5; /* 默认 #429CF5 */
    if (hex.length > 0) {
        NSString *clean = [hex stringByTrimmingCharactersInSet:
            [NSCharacterSet characterSetWithCharactersInString:@"# "]];
        NSScanner *scanner = [NSScanner scannerWithString:clean];
        [scanner scanHexInt:&rgb];
    }
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

@implementation AirSurface

/* 各层级深色/浅色 alpha（对齐 SKILL §2.7 映射表） */
+ (CGFloat)alphaForLevel:(AirSurfaceLevel)level dark:(BOOL)dark {
    static const CGFloat darkAlphas[5]  = {0.04, 0.06, 0.08, 0.10, 0.12};
    static const CGFloat lightAlphas[5] = {0.50, 0.55, 0.60, 0.65, 0.70};
    NSInteger idx = (NSInteger)MAX(0, MIN(4, (int)level));
    return dark ? darkAlphas[idx] : lightAlphas[idx];
}

+ (UIColor *)containerColorForLevel:(AirSurfaceLevel)level {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        BOOL dark = (traits.userInterfaceStyle == UIUserInterfaceStyleDark);
        return [[UIColor whiteColor] colorWithAlphaComponent:[self alphaForLevel:level dark:dark]];
    }];
}

+ (UIColor *)dimColor {
    /* 暗化背景：禁用态卡片、阴影区（深色白 0.04 叠黑 0.10，浅色白 0.45 叠黑 0.05） */
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        if (traits.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [[UIColor whiteColor] colorWithAlphaComponent:0.04];
        }
        return [[UIColor blackColor] colorWithAlphaComponent:0.05];
    }];
}

+ (UIColor *)brightColor {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        BOOL dark = (traits.userInterfaceStyle == UIUserInterfaceStyleDark);
        return [[UIColor whiteColor] colorWithAlphaComponent:(dark ? 0.14 : 0.75)];
    }];
}

+ (UIColor *)backgroundColor {
    return [self containerColorForLevel:AirSurfaceLevelDefault];
}

+ (UIColor *)cardColor {
    return [self brightColor];
}

+ (UIColor *)cardTitleColor {
    return [[UIColor whiteColor] colorWithAlphaComponent:0.04];
}

+ (UIColor *)itemColor {
    return [self containerColorForLevel:AirSurfaceLevelHigh];
}

+ (UIColor *)onCardColor {
    return [UIColor labelColor];
}

+ (UIColor *)onBackgroundColor {
    return [UIColor secondaryLabelColor];
}

+ (UIColor *)cardColorInfluencedByBackground {
    UIColor *base = [self cardColor];
    CGFloat bgOpacity = [[NSUserDefaults standardUserDefaults] floatForKey:@"general.background_opacity"];
    bgOpacity = MAX(0.0, MIN(1.0, bgOpacity));
    CGFloat factor = 1.0 - bgOpacity * 0.45; /* 1.0 → 0.55 线性映射 */
    return [base colorWithAlphaComponent:CGColorGetAlpha(base.CGColor) * factor];
}

+ (UIBezierPath *)cornerPathForPosition:(AirCardPosition)position bounds:(CGRect)bounds {
    CGFloat outer = AirRadiusXL; /* 28 */
    CGFloat inner = AirRadiusXS; /* 4 */
    switch (position) {
        case AirCardPositionSingle:
            return [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:outer];
        case AirCardPositionTop:
            return [UIBezierPath bezierPathWithRoundedRect:bounds
                                        byRoundingCorners:(UIRectCornerTopLeft | UIRectCornerTopRight)
                                              cornerRadii:CGSizeMake(outer, outer)];
        case AirCardPositionTopStart:
            return [UIBezierPath bezierPathWithRoundedRect:bounds
                                        byRoundingCorners:UIRectCornerTopLeft
                                              cornerRadii:CGSizeMake(outer, outer)];
        case AirCardPositionTopEnd:
            return [UIBezierPath bezierPathWithRoundedRect:bounds
                                        byRoundingCorners:UIRectCornerTopRight
                                              cornerRadii:CGSizeMake(outer, outer)];
        case AirCardPositionMiddle:
            return [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:inner];
        case AirCardPositionBottom:
            return [UIBezierPath bezierPathWithRoundedRect:bounds
                                        byRoundingCorners:(UIRectCornerBottomLeft | UIRectCornerBottomRight)
                                              cornerRadii:CGSizeMake(outer, outer)];
        case AirCardPositionBottomStart:
            return [UIBezierPath bezierPathWithRoundedRect:bounds
                                        byRoundingCorners:UIRectCornerBottomLeft
                                              cornerRadii:CGSizeMake(outer, outer)];
        case AirCardPositionBottomEnd:
            return [UIBezierPath bezierPathWithRoundedRect:bounds
                                        byRoundingCorners:UIRectCornerBottomRight
                                              cornerRadii:CGSizeMake(outer, outer)];
    }
}

+ (void)applyCardStyleToView:(UIView *)view level:(AirSurfaceLevel)level {
    view.backgroundColor = [self containerColorForLevel:level];
    view.layer.cornerRadius = AirRadiusMD;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.borderWidth = 0.5;
    view.layer.borderColor = [AirOutline variantColor].CGColor;
    [AirShadow applyLightShadowToView:view cornerRadius:AirRadiusMD];
}

@end

@implementation AirShadow

+ (void)applyShadowToView:(UIView *)view
                  opacity:(float)opacity
                   radius:(CGFloat)radius
                   offset:(CGSize)offset
             cornerRadius:(CGFloat)cornerRadius {
    view.layer.masksToBounds = NO;
    view.layer.shadowColor = [UIColor blackColor].CGColor;
    view.layer.shadowOpacity = opacity;
    view.layer.shadowRadius = radius;
    view.layer.shadowOffset = offset;
    view.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:view.bounds
                                                       cornerRadius:cornerRadius].CGPath;
}

+ (void)applyLightShadowToView:(UIView *)view cornerRadius:(CGFloat)radius {
    [self applyShadowToView:view opacity:0.10 radius:4 offset:CGSizeMake(0, 2) cornerRadius:radius];
}

+ (void)applyMediumShadowToView:(UIView *)view cornerRadius:(CGFloat)radius {
    [self applyShadowToView:view opacity:0.12 radius:7 offset:CGSizeMake(0, 3) cornerRadius:radius];
}

+ (void)applyHeavyShadowToView:(UIView *)view cornerRadius:(CGFloat)radius {
    [self applyShadowToView:view opacity:0.18 radius:12 offset:CGSizeMake(0, 4) cornerRadius:radius];
}

@end
