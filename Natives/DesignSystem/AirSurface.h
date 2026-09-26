#ifndef AIR_SURFACE_H
#define AIR_SURFACE_H

/* 设计令牌与容器色主场：间距/圆角/阴影常量 + 五级 Surface + Dim/Bright +
 * 语义化访问器（background/card/cardTitle/item）+ CardPosition 拼接圆角。
 * 业务代码只用语义访问器，禁止手写 whiteColor alpha 魔法数字。 */

#import <UIKit/UIKit.h>

/* 间距令牌（单位 pt，对齐 SKILL §4.1） */
static const CGFloat AirSpaceXS   = 3.0;  /* 磁贴 item 内边距 */
static const CGFloat AirSpaceBento = 2.0; /* Bento 卡片拼接间距 */
static const CGFloat AirSpaceSM   = 4.0;  /* 卡片上下外间距 */
static const CGFloat AirSpaceMD   = 6.0;  /* chip 间距 */
static const CGFloat AirSpaceLG   = 8.0;  /* 卡片内 padding 上下 */
static const CGFloat AirSpaceXL   = 12.0; /* Bento 卡片间距 */
static const CGFloat AirSpace2XL  = 14.0; /* contentInset 左右 */
static const CGFloat AirSpace3XL  = 16.0; /* 大卡片内 padding */

/* 圆角档位（仅 4/8/12/16/28 + 胶囊/圆形，cornerCurve 一律 continuous） */
static const CGFloat AirRadiusXS = 4.0;   /* L7 微圆角 */
static const CGFloat AirRadiusSM = 8.0;   /* L1 扁平条目 */
static const CGFloat AirRadiusMD = 12.0;  /* L2 标准卡片 / L4 磁贴 */
static const CGFloat AirRadiusLG = 16.0;  /* L3 大卡片 */
static const CGFloat AirRadiusXL = 28.0;  /* L6 超大卡片/分组外框 */

/* 禁用态透明度（对齐 MD3 DisabledAlpha） */
static const CGFloat AirDisabledAlpha = 0.38;

/* Surface 容器五级（对齐 SKILL §2.7） */
typedef NS_ENUM(NSInteger, AirSurfaceLevel) {
    AirSurfaceLevelLowest = 0, /* 嵌套卡片底色 */
    AirSurfaceLevelLow    = 1, /* L1 扁平条目 */
    AirSurfaceLevelDefault = 2, /* L2 标准卡片 */
    AirSurfaceLevelHigh   = 3, /* L3 详情卡片 */
    AirSurfaceLevelHighest = 4, /* 浮球/FAB/模态 */
};

/* CardPosition 拼接位置（对齐 SKILL §15.2：外圆角 28，内圆角 4，间距 2） */
typedef NS_ENUM(NSInteger, AirCardPosition) {
    AirCardPositionSingle = 0, /* 独立块：四角 28 */
    AirCardPositionTop,        /* 顶部块：上 28，下 4 */
    AirCardPositionTopStart,   /* 左上块：左上 28，其余 4 */
    AirCardPositionTopEnd,     /* 右上块：右上 28，其余 4 */
    AirCardPositionMiddle,     /* 中间块：四角 4 */
    AirCardPositionBottom,     /* 底部块：上 4，下 28 */
    AirCardPositionBottomStart,/* 左下块：左下 28，其余 4 */
    AirCardPositionBottomEnd   /* 右下块：右下 28，其余 4 */
};

/* 主题强调色：默认 #429CF5，可经 general.accent_color 偏好覆盖 */
FOUNDATION_EXPORT UIColor *LAAcentColor(void);

@interface AirSurface : NSObject

/* 原始层级色（内部用深浅自适应，业务优先用下方语义访问器） */
+ (UIColor *)containerColorForLevel:(AirSurfaceLevel)level;
+ (UIColor *)dimColor;
+ (UIColor *)brightColor;

/* 语义化访问器（对齐 SKILL §15.9，业务代码只用这些） */
+ (UIColor *)backgroundColor;   /* 页面背景 */
+ (UIColor *)cardColor;         /* 卡片背景（比页面亮一档） */
+ (UIColor *)cardTitleColor;    /* 卡片标题栏半透明底 */
+ (UIColor *)itemColor;         /* 卡片内嵌 Item 背景 */
+ (UIColor *)onCardColor;       /* 卡片主文字（= labelColor） */
+ (UIColor *)onBackgroundColor; /* 背景上次级文字（= secondaryLabelColor） */

/* 背景透明度联动：随 general.background_opacity 偏好 1.0→0.55 衰减 */
+ (UIColor *)cardColorInfluencedByBackground;

/* CardPosition 拼接圆角路径（外 28 / 内 4） */
+ (UIBezierPath *)cornerPathForPosition:(AirCardPosition)position bounds:(CGRect)bounds;

/* 一键卡片风：半透明基底 + 描边 + 轻阴影 + 12 圆角 continuous */
+ (void)applyCardStyleToView:(UIView *)view level:(AirSurfaceLevel)level;

@end

/* 三档阴影（对齐 SKILL §5.2，masksToBounds 保持 NO，用 shadowPath 保阴影） */
@interface AirShadow : NSObject
+ (void)applyLightShadowToView:(UIView *)view cornerRadius:(CGFloat)radius;
+ (void)applyMediumShadowToView:(UIView *)view cornerRadius:(CGFloat)radius;
+ (void)applyHeavyShadowToView:(UIView *)view cornerRadius:(CGFloat)radius;
@end

#endif /* AIR_SURFACE_H */
