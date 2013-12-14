/*
    Copyright (C) 2013 Eric Wasylishen

    Author:  Eric Wasylishen <ewasylishen@gmail.com>
    Date:  December 2013
    License:  MIT  (see COPYING)
 */

#import "TestCommon.h"

/**
 * Test model object that has a univalued NSString attribute
 */
@interface UnivaluedAttributeModel : COObject
@property (readwrite, strong, nonatomic) NSString *label;
@end