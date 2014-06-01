//
//  NicoCommentUtil.m
//  SmilePlayer2
//
//  Created by pontago on 2014/04/05.
//
//

#import "NicoCommentUtil.h"

@implementation NicoCommentUtil
- (NSInteger)commentPosition:(NSString*)mail {
    NSError *error;
    NSRegularExpression *reCommentPosition = [NSRegularExpression 
      regularExpressionWithPattern:@"(ue|shita)" options:0 error:&error];
    NSTextCheckingResult *match = [reCommentPosition firstMatchInString:mail options:0 range:NSMakeRange(0, mail.length)];

    if ([match numberOfRanges] == 2) {
      NSString *positionString = [mail substringWithRange:[match rangeAtIndex:1]];

      if ([positionString isEqualToString:@"ue"]) {
        return COMMENT_POSITION_TOP;
      }
      else if ([positionString isEqualToString:@"shita"]) {
        return COMMENT_POSITION_BOTTOM;
      }
    }

    return COMMENT_POSITION_NORMAL;
}

- (NSInteger)commentSize:(NSString*)mail {
    NSError *error;
    NSRegularExpression *reCommentSize = [NSRegularExpression 
      regularExpressionWithPattern:@"(big|small)" options:0 error:&error];
    NSTextCheckingResult *match = [reCommentSize firstMatchInString:mail options:0 range:NSMakeRange(0, mail.length)];

    if ([match numberOfRanges] == 2) {
      NSString *sizeString = [mail substringWithRange:[match rangeAtIndex:1]];

      if ([sizeString isEqualToString:@"big"]) {
        return COMMENT_SIZE_BIG;
      }
      else if ([sizeString isEqualToString:@"small"]) {
        return COMMENT_SIZE_SMALL;
      }
    }

    return COMMENT_SIZE_NORMAL;
}

- (NSNumber*)commentColor:(NSString*)mail {
    NSDictionary *colors = @{
      @"red": @(0xff0000),
      @"pink": @(0xff8080),
      @"orange": @(0xffcc00),
      @"yellow": @(0xffff00),
      @"green": @(0x00ff00),
      @"cyan": @(0x00ffff),
      @"blue": @(0x0000ff),
      @"purple": @(0xc000ff),
      @"black": @(0x000000),
      @"niconicowhite": @(0xcccc99),
      @"white2": @(0xcccc99),
      @"truered": @(0xcc0033),
      @"red2": @(0xcc0033),
      @"passionorange": @(0xff6600),
      @"orange2": @(0xff6600),
      @"madyellow": @(0x999900),
      @"yellow2": @(0x999900),
      @"elementalgreen": @(0x00cc66),
      @"green2": @(0x00cc66),
      @"marinblue": @(0x33fffc),
      @"blue2": @(0x33fffc),
      @"nobleviolet": @(0x6633cc),
      @"purple2": @(0x6633cc),
    };

    NSString *colorsString = [[colors allKeys] componentsJoinedByString:@"|"];
    NSError *error;
    NSRegularExpression *reCommentColor = [NSRegularExpression 
      regularExpressionWithPattern:[NSString stringWithFormat:@"(%@)", colorsString]
                           options:0 
                             error:&error];
    NSTextCheckingResult *match = [reCommentColor firstMatchInString:mail options:0 range:NSMakeRange(0, mail.length)];

    if ([match numberOfRanges] == 2) {
      NSString *colorString = [mail substringWithRange:[match rangeAtIndex:1]];

      if (colors[colorString]) {
        return colors[colorString];
      }
    }


    reCommentColor = [NSRegularExpression regularExpressionWithPattern:
      @"#([0-9a-fA-F]+)" options:0 error:&error];
    match = [reCommentColor firstMatchInString:mail options:0 range:NSMakeRange(0, mail.length)];
    if ([match numberOfRanges] == 2) {
      NSString *colorString = [mail substringWithRange:[match rangeAtIndex:1]];
      unsigned int colorVal;
      NSScanner *scanner = [NSScanner scannerWithString:colorString];
      [scanner scanHexInt:&colorVal];

      return @(colorVal);
    }

    return @(0xffffff);
}
@end
