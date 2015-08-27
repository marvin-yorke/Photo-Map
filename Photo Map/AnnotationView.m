//
//  AnnotationView.m
//  Photo Map
//
//  Created by marvin on 27.08.15.
//  Copyright (c) 2015 Alex Shevlyakov. All rights reserved.
//

#import "AnnotationView.h"

@implementation AnnotationView

- (instancetype)initWithAnnotation:(id <MKAnnotation>)annotation reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithAnnotation:annotation reuseIdentifier:reuseIdentifier];
    if (self) {
        CGRect frame = self.frame;
        frame.size = CGSizeMake(16, 16);
        self.frame = frame;
        
        
        self.layer.cornerRadius = 8;
        self.backgroundColor = [UIColor redColor];
        self.layer.borderWidth = 2;
        self.layer.borderColor = [UIColor whiteColor].CGColor;
    }
    
    return self;
}

@end
