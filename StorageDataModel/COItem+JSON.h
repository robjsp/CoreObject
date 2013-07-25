#import <CoreObject/COItem.h>

@interface COItem (JSON)

/**
 * Returns a JSON object representation of the receiver, encoded as UTF-8.
 */
- (NSData *) JSONData;
/**
 * Initializes a COItem with the given JSON serialization, generated by -JSONData.
 */
- (id) initWithJSONData: (NSData *)data;

@end
