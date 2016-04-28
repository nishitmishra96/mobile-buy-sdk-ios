//
//  BUYClient+Customers.m
//  Mobile Buy SDK
//
//  Created by Gabriel O'Flaherty-Chan on 2016-04-04.
//  Copyright © 2016 Shopify Inc. All rights reserved.
//

#import "BUYClient+Customers.h"
#import "BUYClient_Internal.h"
#import "NSDateFormatter+BUYAdditions.h"
#import "BUYCustomer.h"
#import "BUYAccountCredentials.h"
#import "BUYOrder.h"
#import "BUYShopifyErrorCodes.h"

@interface BUYAuthenticatedResponse : NSObject
+ (BUYAuthenticatedResponse *)responseFromJSON:(NSDictionary *)json;
@property (nonatomic, copy) NSString *accessToken;
@property (nonatomic, copy) NSDate *expiry;
@property (nonatomic, copy) NSString *customerID;
@end

@implementation BUYAuthenticatedResponse

+ (BUYAuthenticatedResponse *)responseFromJSON:(NSDictionary *)json
{
	BUYAuthenticatedResponse *response = [BUYAuthenticatedResponse new];
	NSDictionary *access = json[@"customer_access_token"];
	response.accessToken = access[@"access_token"];
	NSDateFormatter *formatter = [NSDateFormatter dateFormatterForPublications];
	response.expiry = [formatter dateFromString:access[@"expires_at"]];
	response.customerID = [NSString stringWithFormat:@"%@", access[@"customer_id"]];
	return response;
}

@end

@implementation BUYClient (Customers)

#pragma mark - Customer

- (NSURLSessionDataTask *)getCustomerWithID:(NSString *)customerID callback:(BUYDataCustomerBlock)block
{
	NSURLComponents *components = [self URLComponentsForCustomerWithID:customerID];
	return [self getRequestForURL:components.URL completionHandler:^(NSDictionary *json, NSURLResponse *response, NSError *error) {
		block((json && !error ? [[BUYCustomer alloc] initWithDictionary:json] : nil), error);
	}];
}

- (NSURLSessionDataTask *)createCustomerWithCredentials:(BUYAccountCredentials *)credentials callback:(BUYDataCustomerTokenBlock)block
{
	NSURLComponents *components = [self URLComponentsForCustomers];
	return [self postRequestForURL:components.URL object:credentials.JSONRepresentation completionHandler:^(NSDictionary *json, NSURLResponse *response, NSError *error) {
		if (json && error == nil) {
			[self createTokenForCustomerWithCredentials:credentials customerJSON:json callback:block];
		}
		else {
			block(nil, nil, error);
		}
	}];
}

- (NSURLSessionDataTask *)createTokenForCustomerWithCredentials:(BUYAccountCredentials *)credentials customerJSON:(NSDictionary *)customerJSON callback:(BUYDataCustomerTokenBlock)block
{
	NSURLComponents *components = [self URLComponentsForCustomerLogin];
	return [self postRequestForURL:components.URL object:credentials.JSONRepresentation completionHandler:^(NSDictionary *json, NSURLResponse *response, NSError *error) {
		if (json && error == nil) {
			BUYAuthenticatedResponse *authenticatedResponse = [BUYAuthenticatedResponse responseFromJSON:json];
			self.customerToken = authenticatedResponse.accessToken;
			
			if (customerJSON == nil) {
				[self getCustomerWithID:authenticatedResponse.customerID callback:^(BUYCustomer *customer, NSError *error) {
					block(customer, self.customerToken, error);
				}];
			}
			else {
				block([[BUYCustomer alloc] initWithDictionary:json], self.customerToken, error);
			}
		}
		else {
			block(nil, nil, error);
		}
	}];
}

- (NSURLSessionDataTask *)loginCustomerWithCredentials:(BUYAccountCredentials *)credentials callback:(BUYDataCustomerTokenBlock)block
{
	return [self createTokenForCustomerWithCredentials:credentials customerJSON:nil callback:block];
}

- (NSURLSessionDataTask *)recoverPasswordForCustomer:(NSString *)email callback:(BUYDataCheckoutStatusBlock)block
{
	NSURLComponents *components = [self URLComponentsForPasswordReset];
	
	return [self postRequestForURL:components.URL object:@{@"email": email} completionHandler:^(NSDictionary *json, NSURLResponse *response, NSError *error) {
		
		NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
		error = error ?: [self extractErrorFromResponse:response json:json];
		
		block(statusCode, error);
	}];
}

- (NSURLSessionDataTask *)renewCustomerTokenWithID:(NSString *)customerID callback:(BUYDataTokenBlock)block
{
	if (self.customerToken) {
		NSURLComponents *components = [self URLComponentsForTokenRenewalWithID:customerID];
		
		return [self putRequestForURL:components.URL body:nil completionHandler:^(NSDictionary *json, NSURLResponse *response, NSError *error) {
			
			NSString *accessToken = nil;
			if (json && error == nil) {
				BUYAuthenticatedResponse *authenticatedResponse = [BUYAuthenticatedResponse responseFromJSON:json];
				accessToken = authenticatedResponse.accessToken;
			}
			
			error = error ?: [self extractErrorFromResponse:response json:json];
			
			block(accessToken, error);
		}];
	}
	else {
		block(nil, [NSError errorWithDomain:kShopifyError code:BUYShopifyError_InvalidCustomerToken userInfo:nil]);
		return nil;
	}
}

- (NSURLSessionDataTask *)activateCustomerWithCredentials:(BUYAccountCredentials *)credentials customerID:(NSString *)customerID customerToken:(NSString *)customerToken callback:(BUYDataCustomerTokenBlock)block
{
	NSURLComponents *components = [self URLComponentsForCustomerActivationWithID:customerID customerToken:customerToken];
	NSData *data = [NSJSONSerialization dataWithJSONObject:credentials.JSONRepresentation options:0 error:nil];
	
	return [self putRequestForURL:components.URL body:data completionHandler:^(NSDictionary *json, NSURLResponse *response, NSError *error) {
		if (json && error == nil) {
			BUYAccountCredentialItem *emailItem = [BUYAccountCredentialItem itemWithKey:@"email" value:json[@"customer"][@"email"]];
			credentials[@"email"] = emailItem;
			[self loginCustomerWithCredentials:credentials callback:block];
		}
		else {
			block(nil, nil, error);
		}
	}];
}

- (NSURLSessionDataTask *)resetPasswordWithCredentials:(BUYAccountCredentials *)credentials customerID:(NSString *)customerID customerToken:(NSString *)customerToken callback:(BUYDataCustomerTokenBlock)block
{
	NSURLComponents *components = [self URLComponentsForCustomerPasswordResetWithCustomerID:customerID customerToken:customerToken];
	NSData *data = [NSJSONSerialization dataWithJSONObject:credentials.JSONRepresentation options:0 error:nil];
	
	return [self putRequestForURL:components.URL body:data completionHandler:^(NSDictionary *json, NSURLResponse *response, NSError *error) {
		if (json && error == nil) {
			BUYAccountCredentialItem *emailItem = [BUYAccountCredentialItem itemWithKey:@"email" value:json[@"customer"][@"email"]];
			credentials[@"email"] = emailItem;
			[self loginCustomerWithCredentials:credentials callback:block];
		}
		else {
			block(nil, nil, error);
		}
	}];
}

- (NSURLSessionDataTask *)getOrdersForCustomerWithCallback:(BUYDataOrdersBlock)block
{
	NSURLComponents *components = [self URLComponentsForCustomerOrders];
	return [self getRequestForURL:components.URL completionHandler:^(NSDictionary *json, NSURLResponse *response, NSError *error) {
		NSArray *ordersJSON = json[@"orders"];
		if (!error && ordersJSON) {
			
			NSMutableArray *container = [NSMutableArray new];
			for (NSDictionary *orderJSON in ordersJSON) {
				[container addObject:[[BUYOrder alloc] initWithDictionary:orderJSON]];
			}
			block([container copy], error);
			
		} else {
			block(nil, error);
		}
	}];
}

#pragma mark - URL Formatting

- (NSURLComponents *)URLComponentsForCustomers
{
	return [self customerURLComponents];
}

- (NSURLComponents *)URLComponentsForCustomerWithID:(NSString *)customerID
{
	return [self customerURLComponentsAppendingPath:customerID];
}

- (NSURLComponents *)URLComponentsForCustomerLogin
{
	return [self customerURLComponentsAppendingPath:@"customer_token"];
}

- (NSURLComponents *)URLComponentsForCustomerActivationWithID:(NSString *)customerID customerToken:(NSString *)customerToken
{
	NSDictionary *queryItems = @{ @"token": customerToken };
	NSString *path = [NSString stringWithFormat:@"%@/activate", customerID];
	return [self customerURLComponentsAppendingPath:path queryItems:queryItems];
}

- (NSURLComponents *)URLComponentsForCustomerPasswordResetWithCustomerID:(NSString *)customerID customerToken:(NSString *)customerToken
{
	NSDictionary *queryItems = @{ @"token": customerToken };
	NSString *path = [NSString stringWithFormat:@"%@/reset", customerID];
	return [self customerURLComponentsAppendingPath:path queryItems:queryItems];
}

- (NSURLComponents *)URLComponentsForPasswordReset
{
	return [self customerURLComponentsAppendingPath:@"recover" queryItems:nil];
}

- (NSURLComponents *)URLComponentsForTokenRenewalWithID:(NSString *)customerID
{
	NSString *path = [NSString stringWithFormat:@"%@/customer_token/renew", customerID];
	return [self customerURLComponentsAppendingPath:path queryItems:nil];
}

- (NSURLComponents *)URLComponentsForCustomerOrders
{
	return [self customerURLComponentsAppendingPath:@"orders" queryItems:nil];
}

#pragma mark - Convenience methods

- (NSURLComponents *)customerURLComponents
{
	return [self customerURLComponentsAppendingPath:nil];
}

- (NSURLComponents *)customerURLComponentsAppendingPath:(NSString *)path
{
	return [self customerURLComponentsAppendingPath:path queryItems:nil];
}

- (NSURLComponents *)customerURLComponentsAppendingPath:(NSString *)path queryItems:(NSDictionary *)queryItems
{
	return [self URLComponentsForAPIPath:@"customers" appendingPath:path queryItems:queryItems];
}

- (NSString *)accessTokenFromHeaders:(NSDictionary *)headers
{
	return [headers valueForKey:BUYClientCustomerAccessToken];
}

@end
