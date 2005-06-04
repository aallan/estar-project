package eSTAR::Logging;

# ---------------------------------------------------------------------------

#+ 
#  Name:
#    eSTAR::Logging

#  Purposes:
#    Perl object to handling logging

#  Language:
#    Perl module

#  Description:
#    This module which handles logging and pretty printing for the
#    eSTAR agents and other major client applicatons.

#  Authors:
#    Alasdair Allan (aa@astro.ex.ac.uk)

#  Revision:
#     $Id: Logging.pm,v 1.5 2005/06/04 03:23:33 aa Exp $

#  Copyright:
#     Copyright (C) 2001 University of Exeter. All Rights Reserved.

#-

# ---------------------------------------------------------------------------

=head1 NAME

eSTAR::Logging - Object to handle logging

=head1 SYNOPSIS

  $log = eSTAR::Logging::get_reference();
  
  $log->print( "An standard message" );
  $log->debug( "An debugging report" );

  $log->warn( "A warning" );
  $log->error( "An error report" );

=head1 DESCRIPTION

Handles logging and pretty print to the screen for the eSTAR agents and
other major applications making use of the eSTAR logging, configuration
and state system.

=cut

# L O A D   M O D U L E S --------------------------------------------------

use strict;
use vars qw/ $VERSION /;
use subs qw/ new set_debug print print_ncr header thread thread2 warn 
             error debug debug_ncr debug_overtype_ncr closeout /;

use File::Spec;
use Time::localtime;
use Config::User;
use Carp;

use eSTAR::Error qw /:try/;
use eSTAR::Constants qw /:status/;

'$Revision: 1.5 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

# G L O B A L S ------------------------------------------------------------

my $esc="\033[";

my $normal = $esc . "39;29m";
my $bold = $esc . "39;29m";

my $blue_bold = $esc . "39;34;1m";
my $blue_norm = $esc . "39;34m";

my $green_bold = $esc . "39;32;1m";
my $green_norm = $esc . "39;32m";

my $red_bold = $esc . "39;31;1m";
my $red_norm = $esc . "39;31m";

my $yellow_bold = $esc . "39;33;1m";
my $yellow_norm = $esc . "39;33m";

my $cyan_bold = $esc . "39;36;1m";
my $cyan_norm = $esc . "39;36m";

my $purple_bold = $esc . "39;35;1m";
my $purple_norm = $esc . "39;35m";

# C O N S T R U C T O R ----------------------------------------------------

# is a single instance class, can only be once instance for the entire
# application. Use get_reference() to grab a reference to the object.
my $SINGLETON;

sub new {
  return $SINGLETON if defined $SINGLETON;

  my $proto = shift;
  my $class = ref($proto) || $proto;

  # bless the query hash into the class
  $SINGLETON = bless { WARN     => undef,
                      ERROR    => undef,
                      STD      => undef, 
                      DEBUG    => undef,
                      PROCESS  => undef,
                      TAGNUM   => undef,
                      TOGGLE   => undef }, $class;
  
  # Configure the object
  $SINGLETON->configure( @_ );
  
  return $SINGLETON;
}

sub get_reference {
  return $SINGLETON if defined $SINGLETON;
  return undef;
}

sub configure {
  my $self = shift;

  # grab the process name
  my $process = eSTAR::Process::get_reference(); 
  $self->{PROCESS} = $process->get_process();
  
  # DEBUGGING
  # ---------
  
  # debugging is on by default
  $self->{TOGGLE} = ESTAR__DEBUG;
  
  # LOG FILES
  # ---------
  
  # Warning log
  $self->{WARN} = 
    File::Spec->catfile(Config::User->Home(), 
                 '.estar', $self->{PROCESS}, 'warn.log' );
    
  # Error log  
  $self->{ERROR} = 
    File::Spec->catfile(Config::User->Home(), 
                 '.estar', $self->{PROCESS}, 'error.log' );
    
  # Standard Output log  
  $self->{STD} = 
   File::Spec->catfile(Config::User->Home(), 
                 '.estar', $self->{PROCESS}, 'output.log' );
    
  # Debugging log 
  $self->{DEBUG} = 
    File::Spec->catfile(Config::User->Home(), 
                 '.estar', $self->{PROCESS}, 'debug.log' );

  # UNIQUE TAG NUMBER
  # -----------------

  # Tag number identifying each individual instance of the class
  my $tagid = sprintf( '%.0f', rand( 1000 ) );
  $self->{TAGNUM} = "TagID#" . $self->{PROCESS} . "#$tagid";

  # CREATE ~/.estar DIRECTORY
  # -------------------------

  # check for .estar directory in the user's home directory, if doesn't 
  # exist create it.

  # create .estar directory
  unless (opendir(DIR, File::Spec->catdir(Config::User->Home(),".estar"))) {
    # make the directory
    mkdir File::Spec->catdir( Config::User->Home(), ".estar" ), 0755;
    if (opendir(DIR, File::Spec->catdir(Config::User->Home(),".estar"))) {
       print "Creating ~/.estar directory\n";
       closedir DIR;
    } else {
       # can't open or create it, odd huh?
       my $error = "Cannot make directory " .
                     File::Spec->catdir( Config::User->Home(), ".estar" );
       throw eSTAR::Error::FatalError($error, ESTAR__FATAL);     
    }
  }
  closedir DIR;

  # CREATE PROCESS DIRECTORY
  # -------------------------

  # create ~/.estar/$self->{PROCESS} subdirectory if needed
  unless ( opendir(DIR, 
         File::Spec->catdir( Config::User->Home(), ".estar", 
	                     $self->{PROCESS} )) ) {
       
     # make the directory
     mkdir File::Spec->catdir( 
       Config::User->Home(), ".estar", $self->{PROCESS} ), 0755;
       
     if ( opendir(DIR, 
          File::Spec->catdir( Config::User->Home(), 
	                      ".estar", $self->{PROCESS} )) ) {
        print "Creating ~/.estar/$self->{PROCESS} directory\n";
        closedir DIR;
     } else {
        # can't open or create it, odd huh?
        my $error = "Cannot make directory " .
          File::Spec->catdir( Config::User->Home(), 
	                      ".estar", $self->{PROCESS} );
        throw eSTAR::Error::FatalError($error, ESTAR__FATAL);     
     }
  }
  closedir DIR;

  # Delete current log files if they exist and create new ones
  # ----------------------------------------------------------
  
  # warning log
  if ( open(FILE, "+>$self->{WARN}" )) {
     print FILE "Warning log opened at " . ctime() . "\n";
     close FILE;   
  }
  
  # error log
  if ( open(FILE, "+>$self->{ERROR}" )) {
     print FILE "Error log opened at " . ctime() . "\n";
     close FILE;
  }
  
  # normal log 
  if ( open(FILE, "+>$self->{STD}" )) {
     print FILE "Normal log opened at " . ctime() . "\n";
     close FILE;
  }
  
  # deubugging log  
  if ( open(FILE, "+>$self->{DEBUG}" )) {
     print FILE "Debugging log opened at " . ctime() . "\n";
     close FILE;
  }
   
}

# M E T H O D S -----------------------------------------------------------

=head1 REVISION

$Id: Logging.pm,v 1.5 2005/06/04 03:23:33 aa Exp $

=head1 METHODS

The following methods are available from this module:

=over 4

=item B<set_debug>

Toggle debugging, return value of current debug flag

=cut

sub set_debug {
  my $self = shift;
  my $debug = shift;
   
  if( $debug == ESTAR__DEBUG ) {
     # turn debugging on
     $self->{TOGGLE} = ESTAR__DEBUG;
     
  } elsif ( $debug == ESTAR__QUIET ) {
     # turn debugging off
     $self->{TOGGLE} = ESTAR__QUIET;
  
  } else {
     # no idea what they want, turn it on
     $self->{TOGGLE} = ESTAR__DEBUG;
  }
  
  return $self->{TOGGLE}; 
  
}     

=item B<print>

Normal messages

=cut

sub print {
  my $self = shift;
  my $string = shift;
   
  # open file and print to file
  my $file = $self->{STD};
  if ( open( STD, ">>$file") ) {
     print STD $string . "\n";
  }
  close STD;
  
  # print to screen
  print $string . "\n";
  
}   
   
  
=item B<print_ncr>

Normal messages

=cut

sub print_ncr {
  my $self = shift;
  my $string = shift;
   
  # open file and print to file
  my $file = $self->{STD};
  if ( open( STD, ">>$file") ) {
     print STD $string . "\n";
  }
  close STD;  
  
  # print to screen if debugging turned on
  print $string;
} 
   
   
   
=item B<header>

Information header messages, usually used to seperate 
blocks of connected logging information

=cut

sub header {
  my $self = shift;
  my $string = shift;
   
  # open file and print to file
  my $file = $self->{STD};
  if ( open( STD, ">>$file") ) {
     print STD "\n" . $string . "\n";
     for my $i ( 0 ... length($string)-1 ) {
        print STD "-";
     }
     print STD "\n";   
  }
  close STD;
  
  # print to screen
  print $cyan_norm . $string . $normal . "\n";
  
}        
 
=item B<thread>

Information messages coming from a spawned thread, handle then like
they were standard prints, but use a different colour to pretty print.

=cut

sub thread {
  my $self = shift;
  my $name = shift;
  my $string = shift;
   
  # open file and print to file
  my $file = $self->{STD};
  if ( open( STD, ">>$file") ) {
     print STD  $name . ": " . $string . "\n";
  }
  close STD;
  
  # print to screen if debuuging is turn on, don't want to hear
  # from dub-threads directly if it isn't.
  if( $self->{TOGGLE} == ESTAR__DEBUG ) {
     print $purple_norm . $name . ": " . $string . $normal . "\n";
  }
}    

=item B<thread2>

Information messages coming from a second spawned thread, handle then like
they were standard prints, but use a different colour (again) to pretty print.

=cut

sub thread2 {
  my $self = shift;
  my $name = shift;
  my $string = shift;
   
  # open file and print to file
  my $file = $self->{STD};
  if ( open( STD, ">>$file") ) {
     print STD  $name . ": " . $string . "\n";
  }
  close STD;
  
  # print to screen if debuuging is turn on, don't want to hear
  # from dub-threads directly if it isn't.
  if( $self->{TOGGLE} == ESTAR__DEBUG ) {
     print $blue_norm . $name . ": " . $string . $normal . "\n";
  }
}      
=item B<warn>

Warning information

=cut

sub warn {
  my $self = shift;
  my $string = shift;
   
  # open file and print to file
  my $file = $self->{WARN};
  if ( open( WARN, ">>$file") ) {
     print WARN $string . "\n";
  }
  close WARN;
  
  # open file and print to file
  $file = $self->{STD};
  if ( open( STD, ">>$file") ) {
     print STD $string . "\n";
  }
  close STD;  
  
  # print to screen
  print $yellow_norm . $string . $normal . "\n";
  
}    
  
=item B<error>

Errors, fatal or otherwise

=cut

sub error {
  my $self = shift;
  my $string = shift;
   
  # open file and print to file
  my $file = $self->{ERROR};
  if ( open( ERR, ">>$file") ) {
     print ERR $string . "\n";
  }
  close ERR;
  
  # open file and print to file
  $file = $self->{STD};
  if ( open( STD, ">>$file") ) {
     print STD $string . "\n";
  }
  close STD;  
  
  # print to screen
  print $red_norm . $string . $normal . "\n";
  
}   
  
=item B<debug>

Debugging messages

=cut

sub debug {
  my $self = shift;
  my $string = shift;
   
  # open file and print to file
  my $file = $self->{DEBUG};
  if ( open( BUG, ">>$file") ) {
     print BUG $string . "\n";
  }
  close BUG;
  
  # open file and print to file
  $file = $self->{STD};
  if ( open( STD, ">>$file") ) {
     print STD "Debug: " . $string . "\n";
  }
  close STD;  
  
  # print to screen if debugging turned on
  if ( $self->{TOGGLE} == ESTAR__DEBUG ) {
     print $green_norm . $string . $normal . "\n";
  }
} 

  
=item B<debug_ncr>

Debugging messages

=cut

sub debug_ncr {
  my $self = shift;
  my $string = shift;
   
  # open file and print to file
  my $file = $self->{DEBUG};
  if ( open( BUG, ">>$file") ) {
     print BUG $string . "\n";
  }
  close BUG;
  
  # open file and print to file
  $file = $self->{STD};
  if ( open( STD, ">>$file") ) {
     print STD "Debug: " . $string . "\n";
  }
  close STD;  
  
  # print to screen if debugging turned on
  if ( $self->{TOGGLE} == ESTAR__DEBUG ) {
     print $green_norm . $string . $normal;
  }
} 

  
=item B<debug_overtype_ncr>

Debugging messages

=cut

sub debug_overtype_ncr {
  my $self = shift;
  my $string = shift;
   
  # open file and print to file
  my $file = $self->{DEBUG};
  if ( open( BUG, ">>$file") ) {
     print BUG $string . "\n";
  }
  close BUG;
  
  # open file and print to file
  $file = $self->{STD};
  if ( open( STD, ">>$file") ) {
     print STD "Debug: " . $string . "\n";
  }
  close STD;  
    
  # print to screen if debugging turned on
  if ( $self->{TOGGLE} == ESTAR__DEBUG ) {
     
     my $backspace = "";
     foreach ( 0 ... 80 ) {
        $backspace = $backspace . "\b";
     }
     print $green_norm . $backspace . $string . $normal;
  }
} 
=item B<closeout>

Print closing tags to all log files

=cut

sub closeout {
  my $self = shift;
   
  # open output.log file and print to file
  my $file = $self->{STD};
  if ( open( STD, ">>$file") ) {
     print STD "Normal log closed at " . ctime() . "\n";
  }
  close STD;

  # open warn.log file and print to file
  $file = $self->{WARN};
  if ( open( WARN, ">>$file") ) {
     print WARN "Warning log closed at " . ctime() . "\n";
  }
  close WARN;

  # open error.log file and print to file
  $file = $self->{ERROR};
  if ( open( ERR, ">>$file") ) {
     print ERR "Error log closed at " . ctime() . "\n";
  }
  close ERR;  

  # open debug.log file and print to file
  $file = $self->{DEBUG};
  if ( open( BUG, ">>$file") ) {
     print BUG "Debugging log closed at " . ctime() . "\n";
  }
  close BUG;  
  
}   

# T I M E   A T   T H E   B A R  --------------------------------------------

=back

=head1 COPYRIGHT

Copyright (C) 2002 University of Exeter. All Rights Reserved.

This program was written as part of the eSTAR project and is free software;
you can redistribute it and/or modify it under the terms of the GNU Public
License.

=head1 AUTHORS

Alasdair Allan E<lt>aa@astro.ex.ac.ukE<gt>,

=cut

# L A S T  O R D E R S ------------------------------------------------------

1;                                                                  
