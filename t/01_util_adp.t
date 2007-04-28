#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 11;

use lib $ENV{ESTAR_PERL5LIB};
use eSTAR::ADP::Util qw (:all);
use DateTime;
use DateTime::Duration;

{  # Test read_n_col_header...   
   my $in_file = 'data/two_cols.dat';
   my @expected = ( 
                     ['row0_col0', 'row1_col0', 'row2_col0'],
                     ['row0_col1', 'row1_col1', 'row2_col1'],
                   );

   my @found = read_n_column_file($in_file);
   is_deeply(\@found, \@expected, 'read_n_column_file - two column file');
}


{ # Test get_first_datetime...

   my @dates = (
                 DateTime->new(
                                month => 4,
                                year  => 1995),
                 DateTime->new(
                                month => 1,
                                year  => 1995),
                 DateTime->new(
                                year  => 2016),                                            
                );
   
   is_deeply(get_first_datetime(@dates), DateTime->new(month => 1, year =>1995),
             'get_first_datetime');
}



{ # Test datetime_strs2theorytimes...
   my @dts = qw( 
                 2007-01-01T05:30:29
                 2007-01-01T14:00:00
                 2007-01-08T08:17:17
                );

   my $first = DateTime->new(hour => 2, second => 52,  year => 2007);
   my $days = 10;
   my $runlength = DateTime::Duration->new(hours => $days * 24);
   my @expected = (
                    0.014556712962963,
                    0.0499398148148148,
                    0.726140046296296,
                   );
   my @received = datetime_strs2theorytimes($first, $runlength, @dts);
   
   is_deeply(\@expected, \@received, 'datetimes2theorytimes');


   my $now = $first + DateTime::Duration->new(hours => 17);
}



{ # Test theorytime2datetime...
   my $first = DateTime->new(hour => 2, second => 52,  year => 2007);

   my $days = 10;
   my $runlength = DateTime::Duration->new(hours => $days * 24);
   
   my $theorytime = 0.6;
   
   my $expected = DateTime->new(hour => 2, second => 52, year => 2007, 
                                day => 7);
   
is_deeply(theorytime2datetime($theorytime, $first, $runlength), $expected, 
          'theorytime2datetime');
}


{ # Test str2datetime...
   my $time_str1 = '2007-04-23T03:58:12';
   my $expected_dt1 = DateTime->new(year => 2007, month => 4,  day    => 23, 
                                    hour => 3,   minute => 58, second => 12);

   is_deeply(str2datetime($time_str1), $expected_dt1, 'str2datetime - no UTC tail');

   my $time_str2 = '2007-04-23T03:58:12+0000';
   my $expected_dt2 = DateTime->new(year => 2007, month => 4,  day    => 23, 
                                    hour => 3,   minute => 58, second => 12);

   is_deeply(str2datetime($time_str2), $expected_dt2, 'str2datetime - UTC = +0000');


   my $time_str3 = '2007-04-23T03:58:12-0000';
   my $expected_dt3 = DateTime->new(year => 2007, month => 4,  day    => 23, 
                                    hour => 3,   minute => 58, second => 12);

   is_deeply(str2datetime($time_str3), $expected_dt3, 'str2datetime - UTC = -0000');


   # e.g For UK summer time, which is UTC+1
   my $time_str4 = '2007-04-23T03:58:12+0100';
   my $expected_dt4 = DateTime->new(year => 2007, month => 4,  day    => 23, 
                                    hour => 4,   minute => 58, second => 12);


   is_deeply(str2datetime($time_str4), $expected_dt4, 'str2datetime - UTC = +0100');


   # e.g. For Hawaii, which is UTC-10
   my $time_str5 = '2007-04-23T17:58:12-1000';
   my $expected_dt5 = DateTime->new(year => 2007, month => 4,  day    => 23, 
                                    hour => 7,   minute => 58, second => 12);


   is_deeply(str2datetime($time_str5), $expected_dt5, 'str2datetime - UTC = -1000');


   # Crossing date boundary...
   my $time_str6 = '2007-04-23T06:58:12-1000';
   my $expected_dt6 = DateTime->new(year => 2007, month => 4,  day    => 22, 
                                    hour => 20,   minute => 58, second => 12);

   is_deeply(str2datetime($time_str6), $expected_dt6, 
             'str2datetime - UTC = -1000 (cross date boundary)');
   
   
}


{ # Test datetime2utc_str...
   my $dt = DateTime->new(hour => 2, second => 52, month=> 4, year => 2007);

   is(datetime2utc_str($dt), '2007-04-01T02:00:52+0000', 'datetime2utc_str - in UTC');
}
