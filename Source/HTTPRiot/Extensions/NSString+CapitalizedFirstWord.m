//
//  NSString+CapitalizeFirstWord.m
//  HTTPRiot
//
//  Created by Michael Schrag on 8/9/09.
//  Copyright 2009 m Dimension Technology. All rights reserved.
//

#import "NSString+CapitalizedFirstWord.h"


@implementation NSString (CapitalizedFirstWord)

- (NSString *)capitalizedFirstWord {
    NSUInteger length = [self length];
    if (length > 1) {
        return [NSString stringWithFormat:@"%@%@", [[self substringToIndex:1] uppercaseString], [self substringFromIndex:1]];
    }
    else if (length == 1) {
        return [self uppercaseString];
    }
    else {
        return self;
    }
}

@end
