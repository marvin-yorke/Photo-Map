//
//  PhotoAnnotation.h
//  Photo Map
//
//  Created by Alex on 6/28/13.
//  Copyright (c) 2013 Alex Shevlyakov. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>

@interface PhotoAnnotation : NSObject <MKAnnotation, NSCoding> {
    double latitude;
    double longitude;
}

- (id)initWithImagePath:(NSString *)imagePath title:(NSString *)title coordinate:(CLLocationCoordinate2D)coord;

@property (nonatomic) CLLocationCoordinate2D coordinate;
@property (nonatomic) CLLocationCoordinate2D actualCoordinate;
@property (nonatomic) MKMapPoint mapPoint;

@property (nonatomic, strong) PhotoAnnotation *clusterAnnotation;
@property (nonatomic, strong) NSArray *containedAnnotations;

//- (void)updateSubtitleIfNeeded;

@end
