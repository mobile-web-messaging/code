//
//  MWMViewController.m
//  TruckTracker
//
//  Created by Jeff Mesnil on 24/01/2014.
//  Copyright (c) 2014 Mobile & Web Messaging. All rights reserved.
//

#import "MWMViewController.h"
#import <CoreLocation/CoreLocation.h>
#import <StompKit.h>

#define kHost     @"192.168.1.25"
#define kPort     61613

@interface MWMViewController () <CLLocationManagerDelegate, UITableViewDataSource, UITableViewDelegate>

@property (weak, nonatomic) IBOutlet UILabel *truckIDLabel;
@property (weak, nonatomic) IBOutlet UILabel *currentPositionLabel;
@property (weak, nonatomic) IBOutlet UITableView *tableView;

@property (nonatomic, strong) CLLocationManager *locationManager;

@property (nonatomic, copy) NSString *truckID;

@property (nonatomic, strong) STOMPClient *client;

@end

@implementation MWMViewController

// the orders are stored in an array of NSString.
NSMutableArray *orders;
STOMPSubscription *subscription;

- (void)viewDidLoad
{
    [super viewDidLoad];

    //self.truckID = [UIDevice currentDevice].identifierForVendor.UUIDString;
    self.truckID = @"66284AB0-C266-4A4D-9443-FEFB5774FA3C";
    NSLog(@"Truck identifier is %@", self.truckID);
    self.client = [[STOMPClient alloc] initWithHost:kHost port:kPort];
    
    orders = [[NSMutableArray alloc] init];
}

- (void)viewWillAppear:(BOOL)animated
{
    self.truckIDLabel.text = self.truckID;
    
    [self startUpdatingCurrentLocation];
    [self connect];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [self stopUpdatingCurrentLocation];
    [subscription unsubscribe];
    [self disconnect];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - CoreLocation actions

- (void)startUpdatingCurrentLocation
{
    NSLog(@"startUpdatingCurrentLocation");
    
    // if location services are restricted do nothing
    if ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusDenied ||
        [CLLocationManager authorizationStatus] == kCLAuthorizationStatusRestricted) {
        return;
    }
    
    // if locationManager does not currently exist, create it
    if (!self.locationManager) {
        self.locationManager = [[CLLocationManager alloc] init];
        // set its delegate to self
        self.locationManager.delegate = self;
        // use the accuracy best suite for navigation
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
    }
    
    // start updating the location
    [self.locationManager startUpdatingLocation];
}

- (void)stopUpdatingCurrentLocation
{
    [self.locationManager stopUpdatingLocation];
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager
    didUpdateToLocation:(CLLocation *)newLocation
           fromLocation:(CLLocation *)oldLocation
{
    // ignore if the location is older than 30s
    if (fabs([newLocation.timestamp timeIntervalSinceDate:[NSDate date]]) > 30) {
        return;
    }
    
    CLLocationCoordinate2D coord = [newLocation coordinate];
    self.currentPositionLabel.text = [NSString stringWithFormat:@"φ:%.4F, λ:%.4F", coord.latitude, coord.longitude];

    // send a message with the location data
    [self sendLocation:newLocation];
}

- (void)locationManager:(CLLocationManager *)manager
       didFailWithError:(NSError *)error
{
    // reset the current position label
    self.currentPositionLabel.text = @"Current position: ???";
    
    // show the error alert
    UIAlertView *alert = [[UIAlertView alloc] init];
    alert.title = @"Error obtaining location";
    alert.message = [error localizedDescription];
    [alert addButtonWithTitle:@"OK"];
    [alert show];
}

#pragma mark - UITableViewDelegate

// no delegate actions

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [orders count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // this identifier must be the same that was set in the
    // Table View Cell properties in the story board.
    static NSString *CellIdentifier = @"TruckOrderCell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    
    cell.textLabel.text = [orders objectAtIndex:indexPath.row];
    return cell;
}

#pragma mark - Messaging

- (void)connect
{
    NSLog(@"Connecting...");
    [self.client connectWithHeaders:@{ @"client-id": self.truckID}
                  completionHandler:^(STOMPFrame *connectedFrame, NSError *error) {
                      if (error) {
                          // We have not been able to connect to the broker.
                          // Let's log the error
                          NSLog(@"Error during connection: %@", error);
                      } else {
                          // we are connected to the STOMP broker without an error
                          NSLog(@"Connected");
                          [self subscribe];
                      }
                  }];
    // when the method returns, we can not assume that the client is connected
}

- (void)disconnect
{
    NSLog(@"Disconnecting...");
    [self.client disconnect:^(NSError *error) {
        if (error) {
            NSLog(@"Error during disconnection: %@", error);
        } else {
            // the client is disconnected from the broker without any problem
            NSLog(@"Disconnected");
        }
    }];
    // when the method returns, we can not assume that the client is disconnected
}

- (void)sendLocation:(CLLocation *)location
{
    // build a static NSDateFormatter to display the current date in ISO-8601
    static NSDateFormatter *dateFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = @"yyyy-MM-d'T'HH:mm:ssZZZZZ";
    });

    // send the message to the truck's topic
    NSString *destination = [NSString stringWithFormat:@"/topic/truck.%@.position", self.truckID];

    // build a dictionary containing all the information to send
    NSDictionary *dict = @{
        @"truck": self.truckID,
        @"lat": [NSNumber numberWithDouble:location.coordinate.latitude],
        @"lng": [NSNumber numberWithDouble:location.coordinate.longitude],
        @"ts": [dateFormatter stringFromDate:location.timestamp]
    };
    // create a JSON string from this dictionary
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    NSString *body =[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    NSDictionary *headers = @{
        @"content-type": @"application/json; charset=utf-8"
    };
    
    // send the message
    [self.client sendTo:destination
                headers:headers
                   body:body];
}

- (void)subscribe
{
    // susbscribes to the truck's orders queue:
    NSString *destination = [NSString stringWithFormat:@"/queue/truck.%@.orders", self.truckID];
    
    NSLog(@"subscribing to %@", destination);
    subscription = [self.client subscribeTo:destination
                                    headers:@{}
                             messageHandler:^(STOMPMessage *message) {
        // called every time a message is consumed from the orders destination
        NSLog(@"received message %@", message);
        NSData *data = [message.body dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data
                                                             options:NSJSONReadingMutableContainers
                                                               error:nil];
        NSString *order = dict[@"order"];
        NSLog(@"adding order = %@", order);
        [orders addObject:order];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView reloadData];
        });
    }];
}

- (BOOL)process:(STOMPMessage *)message
{
    return YES;
}

- (void)foo {
    
    NSString *destination = @"...";
    // kHeaderAck and kAckClient constants are defined in StompKit.h
    STOMPSubscription *subscription = [self.client subscribeTo:destination
                                                       headers:@{kHeaderAck: kAckClient}
                                                messageHandler:^(STOMPMessage *message) {
                                                    // process the message
                                                    //...
                                                    
                                                    // acknowledge it
                                                    [message ack];
                                                    // or you can nack it by calling [message nack] instead
                                                }];
    
}

@end
