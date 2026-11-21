#import <UIKit/UIKit.h>

#import "noshi_country_book.h"

@class NoshiCountryController;

@protocol NoshiCountryControllerDelegate <NSObject>
- (void)countryController:(NoshiCountryController *)controller didPickCountry:(NoshiCountry *)country;
- (void)countryControllerDidCancel:(NoshiCountryController *)controller;
@end

/* the country list with search, shown over the phone screen */
@interface NoshiCountryController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

- (id)initWithCountryBook:(NoshiCountryBook *)book;

@property (nonatomic, assign) id<NoshiCountryControllerDelegate> delegate;

@end
