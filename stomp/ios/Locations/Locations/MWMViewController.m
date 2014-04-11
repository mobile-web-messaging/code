//
//  MWMViewController.m
//  Locations
//
//  Created by Jeff Mesnil on 13/03/2014.
//  Copyright (c) 2014 Mobile & Web Messaging. All rights reserved.
//

#import "MWMViewController.h"
#import <CoreLocation/CoreLocation.h>
#import <StompKit.h>

#define kHost     @"jeff.local"
#define kPort     61613

@interface MWMViewController () <CLLocationManagerDelegate, UITableViewDataSource, UITableViewDelegate>

@property (weak, nonatomic) IBOutlet UILabel *deviceIDLabel;
@property (weak, nonatomic) IBOutlet UILabel *currentPositionLabel;
@property (weak, nonatomic) IBOutlet UITableView *tableView;

@property (copy, nonatomic) NSString *deviceID;

@property (strong, nonatomic) CLLocationManager *locationManager;
@property (strong, nonatomic) CLLocation *lastKnownLocation;

@property (nonatomic, strong) STOMPClient *client;

@end

@implementation MWMViewController

// the texts are stored in an array of NSString.
NSMutableArray *texts;
STOMPSubscription *subscription;

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.deviceID = [UIDevice currentDevice].identifierForVendor.UUIDString;
    self.deviceID = @"2262EC25-E9FD-4578-BADE-4E113DE45934";
    NSLog(@"Device identifier is %@", self.deviceID);

    self.client = [[STOMPClient alloc] initWithHost:kHost port:kPort];

    texts = [[NSMutableArray alloc] init];
}

- (void)viewWillAppear:(BOOL)animated
{
    self.deviceIDLabel.text = self.deviceID;

    [self startUpdatingCurrentLocation];
    [self connect];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [self stopUpdatingCurrentLocation];
    [subscription unsubscribe];
    [self disconnect];
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

#pragma mark - CLLocationManagerDelegate protocol

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
    // store the location to send it again when user shakes the device
    self.lastKnownLocation = newLocation;
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

#pragma mark - User Events

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event
{
    if (motion == UIEventSubtypeMotionShake) {
        NSLog(@"device is shaked");
        if (self.lastKnownLocation) {
            [self sendLocation:self.lastKnownLocation];
        }
    }
}


#pragma mark - Messaging

- (void)connect
{
    NSLog(@"Connecting...");
    self.client.errorHandler = ^(NSError* error) {
        NSLog(@"got error from STOMP: %@", error);
    };
    // will send a heartbeat at most every minute.
    // expect broker's heartbeat at least every 20 seconds.
    NSString *heartbeat = @"60000,20000";
    [self.client connectWithHeaders:@{ @"client-id": self.deviceID,
                                       kHeaderHeartBeat: heartbeat }
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
    NSString *destination = [NSString stringWithFormat:@"/topic/device.%@.location", self.deviceID];
    
    // build a dictionary containing all the information to send
    NSDictionary *dict = @{
        @"deviceID": self.deviceID,
        @"lat": [NSNumber numberWithDouble:location.coordinate.latitude],
        @"lng": [NSNumber numberWithDouble:location.coordinate.longitude],
        @"ts": [dateFormatter stringFromDate:location.timestamp]
    };
    // create a JSON string from this dictionary
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    NSString *body =[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    NSDictionary *headers = @{
        @"content-type": @"application/json;charset=utf-8"
    };
    
    // send the message
    [self.client sendTo:destination
                headers:headers
                   body:body];
}

- (void)subscribe
{
    // susbscribes to the device text queue:
    NSString *destination = [NSString stringWithFormat:@"/queue/device.%@.text", self.deviceID];
    
    NSLog(@"subscribing to %@", destination);
    subscription = [self.client subscribeTo:destination
                                    headers:@{}
                             messageHandler:^(STOMPMessage *message) {
        // called every time a message is consumed from the destination
        NSLog(@"received message %@", message);
        // the text is send in a plain String, we use it as is.
        NSString *text = message.body;
        NSLog(@"adding text = %@", text);
        [texts addObject:text];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView reloadData];
        });
    }];
}

-(void)ack
{
    NSString *destination = @"";

    // use client acknowledgement
    [self.client subscribeTo:destination
                     headers:@{kHeaderAck: kAckClient}
              messageHandler:^(STOMPMessage *message) {
                  // process the message
                  // ...

                  // acknowledge it
                  [message ack];
                  // or nack it with
                  // [message nack]
              }];
}

- (void)transaction
{
    NSString *destination = @"";
    NSString *body = @"";

    // begin a transaction
    STOMPTransaction *transaction = [self.client begin];
    // or STOMPTransaction *transaction = [self.client begin:mytxid];
    NSLog(@"started transaction %@", transaction.identifier);

    // send message inside a transaction
    [self.client sendTo:destination
                headers:@{kHeaderTransaction: transaction.identifier}
                   body:body];

    STOMPMessage *message;

    // acknowledge a message inside a transaction
    [message ack:@{kHeaderTransaction: transaction.identifier}];
    // or nack a message inside a transaction with
    // [message nack:@{kHeaderTransaction: transaction.identifier}];

    // commit the transaction
    [transaction commit];
    // or abort it
    [transaction abort];
}

#pragma mark - UITableViewDelegate protocol

// no delegate actions

#pragma mark - UITableViewDataSource protocol

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [texts count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // this identifier must be the same that was set in the
    // Table View Cell properties in the story board.
    static NSString *CellIdentifier = @"TextCell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    
    cell.textLabel.text = [texts objectAtIndex:indexPath.row];
    return cell;
}

@end
