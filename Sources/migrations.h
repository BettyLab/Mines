/* Mines - migrations.h
 __  __
|  \/  | __  ____  ___  ____
|      |(__)|    |/ -_)(__ <
|__\/__||__||__|_|\___//___/
Copyright © 2013-2014 Manuel Sainz de Baranda y Goñi.
Released under the terms of the GNU General Public License v3. */

#import "Theme.h"

Theme* MigratedUserThemeFrom_v1 (NSDictionary*    themeDictionary,
				 NSMutableArray** images,
				 NSError**        error);

// EOF
