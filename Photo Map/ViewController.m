//
//  ViewController.m
//  Photo Map
//
//  Created by Alex Shevlyakov on 27.06.13.
//  Copyright (c) 2013 Alex Shevlyakov. All rights reserved.
//

#import <MapKit/MapKit.h>
#import "ViewController.h"
#import "PhotoAnnotation.h"
#import "AnnotationView.h"
#import "PhotosViewController.h"

#define PINS_COUNT 30000

@implementation ViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {

    }
    return self;
}

#pragma mark - UIViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    _allAnnotationsMapView = [[MKMapView alloc] initWithFrame:CGRectZero];
    
    [self populateWorldWithAllPhotoAnnotations];
}

- (void)populateWorldWithAllPhotoAnnotations
{    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    	
        NSMutableArray *array = [[NSMutableArray alloc] initWithCapacity:PINS_COUNT];
//        for (int i=0; i<PINS_COUNT; i++) {
//            float lat = ((float)rand()/(float)(RAND_MAX)) * 360 - 180;
//            float lon = ((float)rand()/(float)(RAND_MAX)) * 360 - 180;
//            
//            PhotoAnnotation *a = [[PhotoAnnotation alloc] init];
//            a.coordinate = CLLocationCoordinate2DMake(lat, lon);
//            a.actualCoordinate = a.coordinate;
//            a.mapPoint = MKMapPointForCoordinate(a.coordinate);
//            
//            [array addObject:a];
//        }
        
        NSString *data = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"USA-HotelMotel" ofType:@"csv"] encoding:NSASCIIStringEncoding error:nil];
        NSArray *lines = [data componentsSeparatedByString:@"\n"];
        
        NSInteger count = lines.count - 1;
        
        for (NSInteger i = 0; i < count; i+=2) { // do 40k points
            NSString *line = lines[i];
            
            NSArray *components = [line componentsSeparatedByString:@","];
            double latitude = [components[1] doubleValue];
            double longitude = [components[0] doubleValue];
            
            PhotoAnnotation *a = [[PhotoAnnotation alloc] init];
            a.coordinate = CLLocationCoordinate2DMake(latitude, longitude);
            a.actualCoordinate = a.coordinate;
            a.mapPoint = MKMapPointForCoordinate(a.coordinate);

            [array addObject:a];
        }
        
        self.photos = [array copy];

        dispatch_async(dispatch_get_main_queue(), ^{
        	[_allAnnotationsMapView addAnnotations:self.photos];
            [self updateVisibleAnnotations];
        });
    });
}

- (id<MKAnnotation>)annotationInGrid:(MKMapRect)gridMapRect usingAnnotations:(NSSet *)annotations
{
    // First, see if one of the annotations we were already showing is in this MapRect
    NSSet *visibleAnnotationsInBucket = [self.mapView annotationsInMapRect:gridMapRect];
    NSSet *annotationsForGridSet = [annotations objectsPassingTest:^BOOL(id obj, BOOL *stop) {
    	BOOL returnValue = ([visibleAnnotationsInBucket containsObject:obj]);
        if (returnValue)
            *stop = YES;
        return returnValue;
    }];
    
    if (annotationsForGridSet.count != 0) {
        return [annotationsForGridSet anyObject];
    }
    
    // Otherwise, sort the annotations based on their distance from the center of the grid square,
    // then choose the one closest to the center to show
    MKMapPoint centerMapPoint = MKMapPointMake(MKMapRectGetMidX(gridMapRect), MKMapRectGetMidY(gridMapRect));
    NSArray *sortedAnnotations = [[annotations allObjects] sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        CLLocationDistance distance1 = MKMetersBetweenMapPoints(((PhotoAnnotation *)obj1).mapPoint, centerMapPoint);
        CLLocationDistance distance2 = MKMetersBetweenMapPoints(((PhotoAnnotation *)obj2).mapPoint, centerMapPoint);
        
        if (distance1 < distance2) {
            return NSOrderedAscending;
        } else if (distance1 > distance2) {
            return NSOrderedDescending;
        }
        
        return NSOrderedSame;
    }];
    
    return [sortedAnnotations objectAtIndex:0];
}

- (void)updateVisibleAnnotations {
    // Fix performance and visual clutter by calling update when we change map regions
    // This value to controls the number of off screen annotations are displayed.
    // A bigger number means more annotations, less chance of seeing annotation views pop in but decreased performance.
    // A smaller number means fewer annotations, more chance of seeing annotation views pop in but better performance.
    const float marginFactor = 1.0;
    
    // Adjust this roughly based on the dimensions of your annotations views.
    // Bigger numbers more aggressively coalesce annotations (fewer annotations displayed but better performance).
    // Numbers too small result in overlapping annotations views and too many annotations on screen.
    const float bucketSize = [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone ? [UIScreen mainScreen].bounds.size.width / 4 :
    [UIScreen mainScreen].bounds.size.width / 6;
    
    // Find all the annotations in the visible area + a wide margin to avoid popping annotation views in and out while panning the map.
    MKMapRect visibleMapRect = [self.mapView visibleMapRect];
    MKMapRect adjustedVisibleMapRect = MKMapRectInset(visibleMapRect, -marginFactor * visibleMapRect.size.width, -marginFactor * visibleMapRect.size.height);
    
    // Determine how wide each bucket will be, as a MapRect square
    CLLocationCoordinate2D leftCoordinate  = [self.mapView convertPoint:CGPointZero toCoordinateFromView:self.view];
    CLLocationCoordinate2D rightCoordinate = [self.mapView convertPoint:CGPointMake(bucketSize, 0) toCoordinateFromView:self.view];
    double gridSize = MKMapPointForCoordinate(rightCoordinate).x - MKMapPointForCoordinate(leftCoordinate).x;
    MKMapRect gridMapRect = MKMapRectMake(0, 0, gridSize, gridSize);
    
    // Condense annotations, with a padding of two squares, around the visibleMapRect
    double startX = floor(MKMapRectGetMinX(adjustedVisibleMapRect) / gridSize) * gridSize;
    double startY = floor(MKMapRectGetMinY(adjustedVisibleMapRect) / gridSize) * gridSize;
    double endX   = floor(MKMapRectGetMaxX(adjustedVisibleMapRect) / gridSize) * gridSize;
    double endY   = floor(MKMapRectGetMaxY(adjustedVisibleMapRect) / gridSize) * gridSize;
    
    NSMutableSet *annotationsToDelete = [[NSMutableSet alloc] initWithCapacity:self.mapView.annotations.count];
    
    // For each square in our grid, pick one annotation to show
    for (gridMapRect.origin.y = startY; MKMapRectGetMinY(gridMapRect) <= endY; gridMapRect.origin.y += gridSize) {
        for (gridMapRect.origin.x = startX; MKMapRectGetMinX(gridMapRect) <= endX; gridMapRect.origin.x += gridSize) {
            
            NSSet *visibleAnnotationsInBucket = [self.mapView annotationsInMapRect:gridMapRect];
            NSMutableSet *allAnnotationsInBucket = [[_allAnnotationsMapView annotationsInMapRect:gridMapRect] mutableCopy];
            
            if (allAnnotationsInBucket.count > 0) {
                PhotoAnnotation *annotationForGrid = (PhotoAnnotation *)[self annotationInGrid:gridMapRect
                                                                              usingAnnotations:allAnnotationsInBucket];
                
                [allAnnotationsInBucket removeObject:annotationForGrid];
                
                // Give the annotationForGrid a reference to all the annotations it will represent
                annotationForGrid.containedAnnotations = [allAnnotationsInBucket allObjects];
                
                [self.mapView addAnnotation:annotationForGrid];
                
                for (PhotoAnnotation *annotation in allAnnotationsInBucket) {
                    // Give all the other annotations a reference to the one which is representing them
                    annotation.clusterAnnotation = annotationForGrid;
                    annotation.containedAnnotations = nil;
                    
                    // Remove annotations which we've decided to cluster
                    if ([visibleAnnotationsInBucket containsObject:annotation]) {
                        //[self.mapView removeAnnotation:annotation];
                        
                        CLLocationCoordinate2D actualCoordinate = annotation.coordinate;
                        [UIView animateWithDuration:0.3 animations:^{
                            annotation.coordinate = annotation.clusterAnnotation.coordinate;
                        } completion:^(BOOL finished) {
                            annotation.coordinate = actualCoordinate;
                            [self.mapView removeAnnotation:annotation];
                        }];
                    }
                }
            }
        }
    }
}


#pragma mark - MKMapViewDelegate

- (void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated
{
    [self updateVisibleAnnotations];
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation
{
    if (mapView != self.mapView)
        return nil;
    
    if ([annotation isKindOfClass:[PhotoAnnotation class]]) {
    	AnnotationView *annotationView = (AnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:@"Photo"];
        if (annotationView == nil)
            annotationView = [[AnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"Photo"];
        
        return annotationView;
    }
    return nil;
}

- (void)addBounceAnnimationToView:(UIView *)view
{
    CAKeyframeAnimation *bounceAnimation = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    
    bounceAnimation.values = @[@(0.05), @(1.1), @(0.9), @(1)];
    
    bounceAnimation.duration = 0.6;
    NSMutableArray *timingFunctions = [[NSMutableArray alloc] initWithCapacity:bounceAnimation.values.count];
    for (NSUInteger i = 0; i < bounceAnimation.values.count; i++) {
        [timingFunctions addObject:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    }
    [bounceAnimation setTimingFunctions:timingFunctions.copy];
    bounceAnimation.removedOnCompletion = NO;
    
    [view.layer addAnimation:bounceAnimation forKey:@"bounce"];
}

- (void)mapView:(MKMapView *)mapView didAddAnnotationViews:(NSArray *)views
{
    for (MKAnnotationView *annotationView in views) {
        if (![annotationView.annotation isKindOfClass:[PhotoAnnotation class]])
            continue;
        
        PhotoAnnotation *annotation = (PhotoAnnotation *)annotationView.annotation;
        
        if (annotation.clusterAnnotation != nil) {
            // Animate the annotation from it's old container's coordinate, to its actual coordinate
            CLLocationCoordinate2D actualCoordinate = annotation.coordinate;
            CLLocationCoordinate2D containerCoordinate = annotation.clusterAnnotation.coordinate;
            
            annotation.clusterAnnotation = nil;
            annotation.coordinate = actualCoordinate;
            
            [self addBounceAnnimationToView:annotationView];
        }
    }
}

@end
