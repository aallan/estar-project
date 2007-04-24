#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 4;

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
