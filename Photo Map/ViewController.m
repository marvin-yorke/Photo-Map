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
#import "CAAnimation+Blocks.h"

#define PINS_COUNT 30000

@interface ViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) NSMutableDictionary *annotationsCache;
@property (nonatomic, strong) NSOperationQueue *queue;
@end

@implementation ViewController

#pragma mark - UIViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    _allAnnotationsMapView = [[MKMapView alloc] initWithFrame:CGRectZero];
    
    [self populateWorldWithAllPhotoAnnotations];
    
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinch:)];
    pinch.delegate = self;
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    pan.delegate = self;
    
    [self.mapView addGestureRecognizer:pinch];
    [self.mapView addGestureRecognizer:pan];
    
    self.mapView.rotateEnabled = NO;
    self.mapView.showsPointsOfInterest = NO;
    
    self.queue = [[NSOperationQueue alloc] init];
    self.queue.maxConcurrentOperationCount = 1;
}

- (void)populateWorldWithAllPhotoAnnotations
{    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    	
        NSMutableArray *array = [[NSMutableArray alloc] initWithCapacity:30000];

//        NSString *data = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"USA-HotelMotel" ofType:@"csv"] encoding:NSASCIIStringEncoding error:nil];
//        NSArray *lines = [data componentsSeparatedByString:@"\n"];
//        
//        NSInteger count = lines.count - 1;
//        
//        for (NSInteger i = 0; i < count; i+=2) { // do 40k points
//            NSString *line = lines[i];
//            
//            NSArray *components = [line componentsSeparatedByString:@","];
//            double latitude = [components[1] doubleValue];
//            double longitude = [components[0] doubleValue];
//            
//            PhotoAnnotation *a = [[PhotoAnnotation alloc] init];
//            a.coordinate = CLLocationCoordinate2DMake(latitude, longitude);
//            a.actualCoordinate = a.coordinate;
//            a.mapPoint = MKMapPointForCoordinate(a.coordinate);
//            a.id = i;
//            
//            [array addObject:a];
//        }
        
    
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[[NSBundle mainBundle]
                                                                                                     pathForResource:@"data" ofType:@"json"]]
                                                             options:0 error:nil];
        
        NSArray *items = json[@"data"];
        
        for (int i=0; i<items.count; i++) {
            NSDictionary *item = items[i];
            
            double lat = [item[@"latitude"] doubleValue];
            double lon = [item[@"longitude"] doubleValue];
            
            PhotoAnnotation *a = [[PhotoAnnotation alloc] init];
            a.coordinate = CLLocationCoordinate2DMake(lat, lon);
            a.actualCoordinate = a.coordinate;
            a.mapPoint = MKMapPointForCoordinate(a.coordinate);
            
            [array addObject:a];
        }
        
        self.photos = [array copy];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [_allAnnotationsMapView addAnnotations:self.photos];
            [self debouncedUpdateVisibleAnnotations];
        });
    });
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
//    [self updateOverlaysWithCellSize:[self cellSizeForZoomScale:<#(MKZoomScale)#>]];
}

inline static double distanceBetweenMapPoints(MKMapPoint p1, MKMapPoint p2)
{
    return sqrt(pow(p1.x - p2.x, 2) + pow(2, p1.y - p2.y));
}

- (id<MKAnnotation>)annotationInGrid:(MKMapRect)gridMapRect usingAnnotations:(NSSet *)annotations visibleAnnotations:(NSSet *)visibleAnnotationsInBucket
{
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
    NSArray *sortedAnnotations = nil;
    
    if (annotations.count > 500) {
        sortedAnnotations = [[annotations allObjects] sortedArrayUsingComparator:^NSComparisonResult(PhotoAnnotation *obj1, PhotoAnnotation *obj2) {
            if (obj1.id < obj2.id) {
                return NSOrderedAscending;
            } else if (obj1.id > obj2.id) {
                return NSOrderedDescending;
            }
            
            return NSOrderedSame;
        }];
    }
    else {
        sortedAnnotations = [[annotations allObjects] sortedArrayUsingComparator:^NSComparisonResult(PhotoAnnotation *obj1, PhotoAnnotation *obj2) {
            CLLocationDistance distance1 = distanceBetweenMapPoints(obj1.mapPoint, centerMapPoint);
            CLLocationDistance distance2 = distanceBetweenMapPoints(obj2.mapPoint, centerMapPoint);
            
            if (distance1 < distance2) {
                return NSOrderedAscending;
            } else if (distance1 > distance2) {
                return NSOrderedDescending;
            }
            
            return NSOrderedSame;
        }];
    }
    
    return [sortedAnnotations objectAtIndex:0];
}

- (void)updateVisibleAnnotations {
    
    static NSTimeInterval t = 0;
    const NSTimeInterval bounce = 0.2;
    
    if (t == 0) {
        t = [[NSDate date] timeIntervalSinceReferenceDate];
        [self debouncedUpdateVisibleAnnotations];
        return;
    }
    
    NSTimeInterval now = [[NSDate date] timeIntervalSinceReferenceDate];
    if (now - t > bounce) {
        // call to actual update no often than bounce time
        [self debouncedUpdateVisibleAnnotations];
    }
}

- (void)invalidateAnnotationsCacheWithNewZoomScale:(MKZoomScale)zoomScale
{
//    NSInteger zoomLevel = TBZoomScaleToZoomLevel(zoomScale);
//    double cellSize = MIN(MKMapSizeWorld.height, MKMapSizeWorld.width) / (3 * pow(2, zoomLevel));
//    
//    NSInteger cellsCountX = ceil(MKMapSizeWorld.width / cellSize);
//    NSInteger cellsCountY = ceil(MKMapSizeWorld.height / cellSize);

    [self.queue cancelAllOperations];
    self.annotationsCache = [[NSMutableDictionary alloc] init];
}

- (id)cachedAnnotationsForX:(NSInteger)x y:(NSInteger)y
{
    NSDictionary *ys = nil;
    @synchronized(self.annotationsCache) {
        ys = [self.annotationsCache[@(x)] copy];
    }
    
    return ys[@(y)];
}

- (void)setAnnotations:(id)annotations forX:(NSInteger)x y:(NSInteger)y
{
    if (annotations == nil) {
        return;
    }
    
    @synchronized(self.annotationsCache) {
        NSMutableDictionary *ys = self.annotationsCache[@(x)];
        if (ys == nil) {
            ys = [[NSMutableDictionary alloc] init];
        }
        ys[@(y)] = annotations;
        
        self.annotationsCache[@(x)] = ys;
    }
}

NSInteger zoomScaleToZoomLevel(MKZoomScale scale)
{
    double totalTilesAtMaxZoom = MKMapSizeWorld.width / 256.0;
    NSInteger zoomLevelAtMaxZoom = log2(totalTilesAtMaxZoom);
    NSInteger zoomLevel = MAX(0, zoomLevelAtMaxZoom + floor(log2f(scale) + 0.5));
    
    return zoomLevel;
}

float cellSizeForZoomScale(MKZoomScale zoomScale)
{
    NSInteger zoomLevel = zoomScaleToZoomLevel(zoomScale);
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        return MIN(MKMapSizeWorld.height, MKMapSizeWorld.width) / (2 * pow(2, zoomLevel));
    }
    return MIN(MKMapSizeWorld.height, MKMapSizeWorld.width) / (3 * pow(2, zoomLevel));
}

- (void)debouncedUpdateVisibleAnnotations {
//    // Fix performance and visual clutter by calling update when we change map regions
//    // This value to controls the number of off screen annotations are displayed.
//    // A bigger number means more annotations, less chance of seeing annotation views pop in but decreased performance.
//    // A smaller number means fewer annotations, more chance of seeing annotation views pop in but better performance.
//    const float marginFactor = 0.0;
//    
//    // Adjust this roughly based on the dimensions of your annotations views.
//    // Bigger numbers more aggressively coalesce annotations (fewer annotations displayed but better performance).
//    // Numbers too small result in overlapping annotations views and too many annotations on screen.
//    const float bucketSize = 40;
    
    static double prevZoomScale;
    
    double zoomScale = self.mapView.bounds.size.width / self.mapView.visibleMapRect.size.width;
    double cellSize = cellSizeForZoomScale(zoomScale);

    if (fabs(prevZoomScale - zoomScale) > DBL_EPSILON) {
        prevZoomScale = zoomScale;
        NSLog(@"zoom level is now %td", zoomScaleToZoomLevel(zoomScale));
        
        [self invalidateAnnotationsCacheWithNewZoomScale:zoomScale];
    }
    
    MKMapRect visibleRect = self.mapView.visibleMapRect;
    
    NSInteger minX = MKMapRectGetMinX(visibleRect) / cellSize;
    NSInteger maxX = MKMapRectGetMaxX(visibleRect) / cellSize + 1;
    NSInteger minY = MKMapRectGetMinY(visibleRect) / cellSize;
    NSInteger maxY = MKMapRectGetMaxY(visibleRect) / cellSize + 1;
    
    if ([_allAnnotationsMapView annotationsInMapRect:visibleRect].count == 0) {
        return;
    }
    
//    [self.mapView removeOverlays:self.mapView.overlays];
    
    for (NSInteger x = minX; x <= maxX; x++) {
        for (NSInteger y = minY; y <= maxY; y++) {
            
//            MKMapPoint points[4];
//            points[0] = MKMapPointMake(x * cellSize, y * cellSize);
//            points[1] = MKMapPointMake(x * cellSize, y * cellSize + cellSize);
//            points[2] = MKMapPointMake(x * cellSize + cellSize, y * cellSize + cellSize);
//            points[3] = MKMapPointMake(x * cellSize + cellSize, y * cellSize);
//            
//            MKPolygon *polygon = [MKPolygon polygonWithPoints:points count:4];
//            [self.mapView addOverlay:polygon];
            
            MKMapRect gridMapRect = MKMapRectMake(x * cellSize, y * cellSize, cellSize, cellSize);
            
            NSSet *visibleAnnotationsInBucket = [self.mapView annotationsInMapRect:gridMapRect];
            PhotoAnnotation *cached = [self cachedAnnotationsForX:x y:y];
            if (cached) {
                if ([visibleAnnotationsInBucket containsObject:cached] == NO) {
                    [self.mapView addAnnotation:cached];
                }
                
                continue;
            }
            
            [self.queue addOperation:[NSBlockOperation blockOperationWithBlock:^{
                NSMutableSet *allAnnotationsInBucket = [[_allAnnotationsMapView annotationsInMapRect:gridMapRect] mutableCopy];
                if (allAnnotationsInBucket.count > 0) {
                    PhotoAnnotation *annotationForGrid = (PhotoAnnotation *)[self annotationInGrid:gridMapRect
                                                                                  usingAnnotations:allAnnotationsInBucket
                                                                                visibleAnnotations:visibleAnnotationsInBucket];
                    
                    [allAnnotationsInBucket removeObject:annotationForGrid];
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.mapView addAnnotation:annotationForGrid];
                    });
                    
                    [self setAnnotations:annotationForGrid forX:x y:y];
                    
                    for (PhotoAnnotation *annotation in allAnnotationsInBucket) {
                        // Give all the other annotations a reference to the one which is representing them
                        annotation.clusterAnnotation = annotationForGrid;
                        
                        // Remove annotations which we've decided to cluster
                        if ([visibleAnnotationsInBucket containsObject:annotation]) {
                            //[self.mapView removeAnnotation:annotation];
                            
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [self hideViewWithBounceAnimation:[self.mapView viewForAnnotation:annotation] completion:^(BOOL finished) {
                                    [self.mapView removeAnnotation:annotation];
                                }];
                            });
                        }
                    }
                }
            }]];
        }
    }
    
//    // remove annotations that are not visible
//    NSMutableSet *allAnnotations = [NSMutableSet setWithArray:self.mapView.annotations];
//    NSSet *visibleAnnotations = [self.mapView annotationsInMapRect:self.mapView.visibleMapRect];
//    [allAnnotations minusSet:visibleAnnotations];
//    
//    [self.mapView removeAnnotations:allAnnotations.allObjects];
}

- (void)addBounceAnnimationToViewAppear:(UIView *)view
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

- (void)hideViewWithBounceAnimation:(UIView *)view completion:(void (^)(BOOL finished))completion;
{
    CAKeyframeAnimation *bounceAnimation = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    
    bounceAnimation.values = @[@1, @0.9, @1.1, @0.05] ;
    
    bounceAnimation.duration = 0.6;
    
    NSMutableArray *timingFunctions = [[NSMutableArray alloc] initWithCapacity:bounceAnimation.values.count];
    for (NSUInteger i = 0; i < bounceAnimation.values.count; i++) {
        [timingFunctions addObject:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    }
    
    [bounceAnimation setTimingFunctions:timingFunctions.copy];
    bounceAnimation.removedOnCompletion = NO;
    bounceAnimation.completion = completion;
    
    [view.layer addAnimation:bounceAnimation forKey:@"bounce"];
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

- (void)mapView:(MKMapView *)mapView didAddAnnotationViews:(NSArray *)views
{
    for (MKAnnotationView *annotationView in views) {
        if (![annotationView.annotation isKindOfClass:[PhotoAnnotation class]])
            continue;
        
        PhotoAnnotation *annotation = (PhotoAnnotation *)annotationView.annotation;
        
        if (annotation.clusterAnnotation != nil) {
            // Animate the annotation from it's old container's coordinate, to its actual coordinate
            annotation.clusterAnnotation = nil;
            annotation.coordinate = annotation.actualCoordinate;
            
            [self addBounceAnnimationToViewAppear:annotationView];
        }
    }
}

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id)overlay
{
    if([overlay isKindOfClass:[MKPolygon class]]) {
        MKPolygonRenderer *renderer = [[MKPolygonRenderer alloc] initWithPolygon:(MKPolygon *)overlay];
        renderer.strokeColor = [[UIColor redColor] colorWithAlphaComponent:0.5];
        return renderer;
    } else {
        return nil;
    }
}

#pragma mark - Gesture recognizers

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (void)pan:(UIPanGestureRecognizer *)rec
{
    [self updateVisibleAnnotations];
}

- (void)pinch:(UIPinchGestureRecognizer *)rec
{
    [self updateVisibleAnnotations];
}

@end
