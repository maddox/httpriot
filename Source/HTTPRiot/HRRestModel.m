//
//  HRRestModel.m
//  HTTPRiot
//
//  Created by Justin Palmer on 1/28/09.
//  Copyright 2009 LabratRevenge LLC.. All rights reserved.
//

#import "HRRestModel.h"
#import "HRRequestOperation.h"

NSString *kHRClassAttributesDelegateKey         = @"delegate";
NSString *kHRClassAttributesNameKey             = @"name";
NSString *kHRClassAttributesBaseURLKey          = @"baseURL";
NSString *kHRClassAttributesHeadersKey          = @"headers";
NSString *kHRClassAttributesBasicAuthKey        = @"basicAuth";
NSString *kHRClassAttributesUsernameKey         = @"username";
NSString *kHRClassAttributesPasswordKey         = @"password";
NSString *kHRClassAttributesFormatKey           = @"format";
NSString *kHRClassAttributesDefaultParamsKey    = @"defaultParams";
NSString *kHRClassAttributesParamsKeys          = @"params";

@interface HRRestModel (PrivateMethods)
+ (void)setAttributeValue:(id)attr forKey:(NSString *)key;
+ (NSMutableDictionary *)classAttributes;
+ (NSMutableDictionary *)mergedOptions:(NSDictionary *)options;
+ (NSOperation *)requestWithMethod:(HRRequestMethod)method path:(NSString *)path options:(NSDictionary *)options object:(id)obj;
+ (NSOperation *)requestWithMethod:(HRRequestMethod)method path:(NSString *)path named:(NSString *)name options:(NSDictionary *)options object:(id)obj selector:(SEL)selector;
@end

@implementation HRRestModel
static NSMutableDictionary *attributes;
+ (void)initialize {    
    if(!attributes)
        attributes = [[NSMutableDictionary alloc] init];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Class Attributes

// Given that we want to allow classes to define default attributes we need to create 
// a classname-based dictionary store that maps a subclass name to a dictionary 
// containing its attributes.
+ (NSMutableDictionary *)classAttributes {
    NSString *className = NSStringFromClass([self class]);
    
    NSMutableDictionary *newDict;
    NSMutableDictionary *dict = [attributes objectForKey:className];
    
    if(dict) {
        return dict;
    } else {
        newDict = [NSMutableDictionary dictionaryWithObject:[NSNumber numberWithInt:HRDataFormatJSON] forKey:@"format"];
        [attributes setObject:newDict forKey:className];
    }
    
    return newDict;
}

+ (NSObject *)delegate {
   return [[self classAttributes] objectForKey:kHRClassAttributesDelegateKey];
}

+ (void)setDelegate:(NSObject *)del {
    [self setAttributeValue:[NSValue valueWithNonretainedObject:del] forKey:kHRClassAttributesDelegateKey];
}

+ (NSURL *)baseURL {
   return [[self classAttributes] objectForKey:kHRClassAttributesBaseURLKey];
}

+ (void)setBaseURL:(NSURL *)uri {
    [self setAttributeValue:uri forKey:kHRClassAttributesBaseURLKey];
}

+ (NSDictionary *)headers {
    return [[self classAttributes] objectForKey:kHRClassAttributesHeadersKey];
}

+ (void)setHeaders:(NSDictionary *)hdrs {
    [self setAttributeValue:hdrs forKey:kHRClassAttributesHeadersKey];
}

+ (NSDictionary *)basicAuth {
    return [[self classAttributes] objectForKey:kHRClassAttributesBasicAuthKey];
}

+ (void)setBasicAuthWithUsername:(NSString *)username password:(NSString *)password {
    NSDictionary *authDict = [NSDictionary dictionaryWithObjectsAndKeys:username, kHRClassAttributesUsernameKey, password, kHRClassAttributesPasswordKey, nil];
    [self setAttributeValue:authDict forKey:kHRClassAttributesBasicAuthKey];
}

+ (HRDataFormat)format {
    return [[[self classAttributes] objectForKey:kHRClassAttributesFormatKey] intValue];
}

+ (void)setFormat:(HRDataFormat)format {
    [[self classAttributes] setValue:[NSNumber numberWithInt:format] forKey:kHRClassAttributesFormatKey];
}

+ (NSDictionary *)defaultParams {
    return [[self classAttributes] objectForKey:kHRClassAttributesDefaultParamsKey];
}

+ (void)setDefaultParams:(NSDictionary *)params {
    [self setAttributeValue:params forKey:kHRClassAttributesDefaultParamsKey];
}

+ (void)setAttributeValue:(id)attr forKey:(NSString *)key {
    [[self classAttributes] setObject:attr forKey:key];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - REST Methods

+ (NSOperation *)getPath:(NSString *)path withOptions:(NSDictionary *)options object:(id)obj {
    return [self requestWithMethod:HRRequestMethodGet path:path options:options object:obj];               
}

+ (NSOperation *)postPath:(NSString *)path withOptions:(NSDictionary *)options object:(id)obj {
    return [self requestWithMethod:HRRequestMethodPost path:path options:options object:obj];                
}

+ (NSOperation *)putPath:(NSString *)path withOptions:(NSDictionary *)options object:(id)obj {
    return [self requestWithMethod:HRRequestMethodPut path:path options:options object:obj];              
}

+ (NSOperation *)deletePath:(NSString *)path withOptions:(NSDictionary *)options object:(id)obj {
    return [self requestWithMethod:HRRequestMethodDelete path:path options:options object:obj];        
}

+ (NSOperation *)getPath:(NSString *)path named:(NSString *)name withOptions:(NSDictionary *)options object:(id)obj selector:(SEL)selector {
    return [self requestWithMethod:HRRequestMethodGet path:path named:name options:options object:obj selector:selector];               
}

+ (NSOperation *)postPath:(NSString *)path named:(NSString *)name withOptions:(NSDictionary *)options object:(id)obj selector:(SEL)selector {
    return [self requestWithMethod:HRRequestMethodPost path:path named:name options:options object:obj selector:selector];                
}

+ (NSOperation *)putPath:(NSString *)path named:(NSString *)name withOptions:(NSDictionary *)options object:(id)obj selector:(SEL)selector {
    return [self requestWithMethod:HRRequestMethodPut path:path named:name options:options object:obj selector:selector];              
}

+ (NSOperation *)deletePath:(NSString *)path named:(NSString *)name withOptions:(NSDictionary *)options object:(id)obj selector:(SEL)selector {
    return [self requestWithMethod:HRRequestMethodDelete path:path named:name options:options object:obj selector:selector];        
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

+ (NSOperation *)requestWithMethod:(HRRequestMethod)method path:(NSString *)path options:(NSDictionary *)options object:(id)obj {
    return [self requestWithMethod:method path:path named:nil options:options object:obj selector:NULL];
}

+ (NSOperation *)requestWithMethod:(HRRequestMethod)method path:(NSString *)path named:(NSString *)name options:(NSDictionary *)options object:(id)obj selector:(SEL)selector {
    NSMutableDictionary *opts = [self mergedOptions:options];
    if (name) {
        [opts setObject:name forKey:@"name"];
    }
    return [HRRequestOperation requestWithMethod:method path:path options:opts object:obj selector:selector];
}

+ (NSMutableDictionary *)mergedOptions:(NSDictionary *)options {
    NSMutableDictionary *defaultParams = [NSMutableDictionary dictionaryWithDictionary:[self defaultParams]];
    [defaultParams addEntriesFromDictionary:[options valueForKey:kHRClassAttributesParamsKeys]];
    
    options = [NSMutableDictionary dictionaryWithDictionary:options];
    [(NSMutableDictionary *)options setObject:defaultParams forKey:kHRClassAttributesParamsKeys];
    NSMutableDictionary *opts = [NSMutableDictionary dictionaryWithDictionary:[self classAttributes]];
    [opts addEntriesFromDictionary:options];
    [opts removeObjectForKey:kHRClassAttributesDefaultParamsKey];

    return opts;
}
@end
