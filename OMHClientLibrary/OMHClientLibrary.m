//
//  OMHClientLibrary.m
//  OMHClient
//
//  Created by Charles Forkish on 12/11/14.
//  Copyright (c) 2014 Open mHealth. All rights reserved.
//

#import "OMHClientLibrary.h"
#import "AFHTTPSessionManager.h"

#import <GooglePlus/GooglePlus.h>
#import <GoogleOpenSource/GoogleOpenSource.h>

NSString * const kDSUBaseURL = @"https://lifestreams.smalldata.io/dsu/";



@implementation OMHTest

+ (void)test
{
    NSLog(@"TEST!!");
}

@end

@interface OMHClient () <GPPSignInDelegate>

@property (nonatomic, strong) GPPSignIn *gppSignIn;
@property (nonatomic, strong) AFHTTPSessionManager *httpSessionManager;

@property (nonatomic, strong) NSString *dsuAccessToken;
@property (nonatomic, strong) NSString *dsuRefreshToken;
@property (nonatomic, strong) NSDate *accessTokenDate;
@property (nonatomic, assign) NSTimeInterval accessTokenValidDuration;

@property (nonatomic, strong) NSMutableArray *pendingDataPoints;

@end

@implementation OMHClient

+ (instancetype)sharedClient
{
    static OMHClient *_sharedClient = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSData *encodedClient = [defaults objectForKey:@"OMHClient"];
        if (encodedClient != nil) {
            _sharedClient = (OMHClient *)[NSKeyedUnarchiver unarchiveObjectWithData:encodedClient];
        } else {
            _sharedClient = [[self alloc] initPrivate];
        }
    });
    
    return _sharedClient;
}

- (instancetype)init
{
    @throw [NSException exceptionWithName:@"Singleton"
                                   reason:@"Use +[OMHClient sharedClient]"
                                 userInfo:nil];
    return nil;
}

- (void)commonInit
{
    //    [self.gppSignIn signOut]; // TODO: remove
}

- (instancetype)initPrivate
{
    self = [super init];
    if (self) {
        [self commonInit];
        
        self.pendingDataPoints = [NSMutableArray array];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super init];
    if (self != nil) {
        _dsuAccessToken = [decoder decodeObjectForKey:@"client.dsuAccessToken"];
        _dsuRefreshToken = [decoder decodeObjectForKey:@"client.dsuRefreshToken"];
        _pendingDataPoints = [decoder decodeObjectForKey:@"client.pendingDataPoints"];
        if (_pendingDataPoints == nil) _pendingDataPoints = [NSMutableArray array]; // TODO: remove
        [_pendingDataPoints removeAllObjects];
        _accessTokenDate = [decoder decodeObjectForKey:@"client.accessTokenDate"];
        _accessTokenValidDuration = [decoder decodeDoubleForKey:@"client.accessTokenValidDuration"];
    }
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeObject:self.dsuAccessToken forKey:@"client.dsuAccessToken"];
    [encoder encodeObject:self.dsuRefreshToken forKey:@"client.dsuRefreshToken"];
    [encoder encodeObject:self.pendingDataPoints forKey:@"client.pendingDataPoints"];
    [encoder encodeObject:self.accessTokenDate forKey:@"client.accessTokenDate"];
    [encoder encodeDouble:self.accessTokenValidDuration forKey:@"client.accessTokenValidDuration"];
}



- (void)saveClientState
{
    NSLog(@"saving client state");
    NSData *encodedClient = [NSKeyedArchiver archivedDataWithRootObject:self];
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:encodedClient forKey:@"OMHClient"];
    [userDefaults synchronize];
}

- (NSString *)encodedClientIDAndSecret
{
    if (self.appDSUClientID == nil || self.appDSUClientSecret == nil) return nil;
    
    NSString *string = [NSString stringWithFormat:@"%@:%@",
                        self.appDSUClientID,
                        self.appDSUClientSecret];
    
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSLog(@"encoded cliend id and secret: %@", [data base64EncodedStringWithOptions:0]);
    return [data base64EncodedStringWithOptions:0];
    
}


#pragma mark - Property Accessors

- (void)setAppGoogleClientID:(NSString *)appGoogleClientID
{
    _appGoogleClientID = appGoogleClientID;
    self.gppSignIn.clientID = appGoogleClientID;
}

- (void)setServerGoogleClientID:(NSString *)serverGoogleClientID
{
    _serverGoogleClientID = serverGoogleClientID;
    self.gppSignIn.homeServerClientID = serverGoogleClientID;
}

- (BOOL)isSignedIn
{
    return (self.dsuAccessToken != nil && self.dsuRefreshToken != nil);
}


#pragma mark - HTTP Session Manager

- (AFHTTPSessionManager *)httpSessionManager
{
    if (_httpSessionManager == nil) {
        _httpSessionManager = [[AFHTTPSessionManager alloc] initWithBaseURL:[NSURL URLWithString:kDSUBaseURL]];
    }
    return _httpSessionManager;
}

- (void)setDSUSignInHeader
{
    NSString *token = [self encodedClientIDAndSecret];
    if (token) {
        self.httpSessionManager.requestSerializer = [AFHTTPRequestSerializer serializer];
        NSString *auth = [NSString stringWithFormat:@"Basic %@", token];
        [self.httpSessionManager.requestSerializer setValue:auth forHTTPHeaderField:@"Authorization"];
    }
}

- (void)setDSUUploadHeader
{
    NSLog(@"setting dsu upload header: %@", self.dsuAccessToken);
    if (self.dsuAccessToken) {
        self.httpSessionManager.requestSerializer = [AFJSONRequestSerializer serializer];
        NSString *auth = [NSString stringWithFormat:@"Bearer %@", self.dsuAccessToken];
        [self.httpSessionManager.requestSerializer setValue:auth forHTTPHeaderField:@"Authorization"];
    }
}

- (void)storeAuthenticationResponse:(NSDictionary *)responseDictionary
{
    self.dsuAccessToken = responseDictionary[@"access_token"];
    self.dsuRefreshToken = responseDictionary[@"refresh_token"];
    self.accessTokenDate = [NSDate date];
    self.accessTokenValidDuration = [responseDictionary[@"expires_in"] doubleValue];
    [self saveClientState];
}

- (void)refreshAuthentication
{
    [self setDSUSignInHeader];
    
    NSString *request = @"oauth/token";
    NSDictionary *parameters = @{@"refresh_token" : self.dsuRefreshToken,
                                 @"grant_type" : @"refresh_token"};
    
    [self.httpSessionManager POST:request parameters:parameters success:^(NSURLSessionDataTask *task, id responseObject) {
        NSLog(@"refresh authentication success: %@", responseObject);
        
        [self storeAuthenticationResponse:(NSDictionary *)responseObject];
        [self uploadPendingDataPoints];
        
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSLog(@"refresh authentiation failed: %@", error);
    }];
}

- (void)submitDataPoint:(NSDictionary *)dataPoint
{
    [self.pendingDataPoints addObject:dataPoint];
    // TODO: check expiry date and don't refresh unless necessary
    [self refreshAuthentication];
}

- (void)uploadPendingDataPoints
{
    NSLog(@"uploading pending data points: %d", (int)self.pendingDataPoints.count);
    [self setDSUUploadHeader];
    for (NSDictionary *dataPoint in self.pendingDataPoints) {
        [self uploadDataPoint:dataPoint];
    }
}

- (void)uploadDataPoint:(NSDictionary *)dataPoint
{
    NSLog(@"uploading data point: %@", dataPoint);
    
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dataPoint
                                                       options:0
                                                         error:nil];
    NSDictionary *dataHeaders = @{@"Content-Disposition" :@"form-data; name=\"data\"",
                                  @"Content-Type" : @"application/json"};
    
    NSString *request = @"dataPoints";
    
    //    [self.httpSessionManager POST:request parameters:nil constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
    //        [formData appendPartWithHeaders:dataHeaders body:jsonData];
    //
    //    }
    [self.httpSessionManager POST:request parameters:dataPoint
                          success:^(NSURLSessionDataTask *task, id responseObject) {
                              NSLog(@"upload data point succeeded: %@", responseObject);
                              NSLog(@"array contains data point: %d", [self.pendingDataPoints containsObject:dataPoint]);
                              [self.pendingDataPoints removeObject:dataPoint];
                          } failure:^(NSURLSessionDataTask *task, NSError *error) {
                              NSLog(@"upload data point failed: %@", error);
                          }];
}



#pragma mark - Google Login

+ (UIButton *)googleSignInButton
{
    GPPSignInButton *googleButton = [[GPPSignInButton alloc] init];
    googleButton.style = kGPPSignInButtonStyleWide;
    return googleButton;
}

- (GPPSignIn *)gppSignIn
{
    if (_gppSignIn == nil) {
        GPPSignIn *signIn = [GPPSignIn sharedInstance];
        signIn.shouldFetchGooglePlusUser = YES;
        signIn.shouldFetchGoogleUserEmail = YES;
        //        signIn.attemptSSO = YES;
        
        signIn.scopes = @[ @"profile" ];
        _gppSignIn = signIn;
        _gppSignIn.delegate = self;
    }
    return _gppSignIn;
}

- (void)finishedWithAuth: (GTMOAuth2Authentication *)auth
                   error: (NSError *) error
{
    NSLog(@"Client received google error %@ and auth object %@",error, auth);
    if (error) {
        
    }
    else {
        NSString *serverCode = [GPPSignIn sharedInstance].homeServerAuthorizationCode;
        NSLog(@"serverCode: %@", serverCode);
        if (serverCode != nil) {
            [self signInToDSUWithServerCode:serverCode];
        }
        else {
            NSLog(@"failed to receive server code from google auth");
        }
    }
}

- (void)signInToDSUWithServerCode:(NSString *)serverCode
{
    [self setDSUSignInHeader];
    
    NSString *request =  @"google-signin";
    NSString *code = [NSString stringWithFormat:@"fromApp_%@", serverCode];
    NSDictionary *parameters = @{@"code": code, @"client_id" : self.appDSUClientID};
    
    [self.httpSessionManager GET:request parameters:parameters success:^(NSURLSessionDataTask *task, id responseObject) {
        NSLog(@"DSU login success, response object: %@", responseObject);
        [self storeAuthenticationResponse:(NSDictionary *)responseObject];
        
        if (self.signInDelegate != nil) {
            [self.signInDelegate OMHClientSignInFinishedWithError:nil];
        }
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSLog(@"DSU login failure, error: %@", error);
        
        if (self.signInDelegate != nil) {
            [self.signInDelegate OMHClientSignInFinishedWithError:error];
        }
    }];
}

- (BOOL)handleURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    return [GPPURLHandler handleURL:url
                  sourceApplication:sourceApplication
                         annotation:annotation];
}

- (void)signOut
{
    [self.gppSignIn signOut];
    
    self.dsuAccessToken = nil;
    self.dsuRefreshToken = nil;
    self.accessTokenDate = nil;
    self.accessTokenValidDuration = 0;
}

@end

