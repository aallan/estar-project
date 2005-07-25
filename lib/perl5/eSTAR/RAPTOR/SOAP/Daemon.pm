package eSTAR::RAPTOR::SOAP::Daemon;

use threads;
use threads::shared;

use strict;
use vars qw(@ISA);

use SOAP::Transport::HTTP::Daemon::ForkAfterProcessing;
#use SOAP::Transport::HTTP::Daemon::ThreadOnAccept;
#use SOAP::Transport::HTTP;

# Code based on WishList::Daemon.pm taken from "Programming Web
# Sercies with Perl" by Ray & Kulchenko.

@ISA = qw(SOAP::Transport::HTTP::Daemon::ForkAfterProcessing);
#@ISA = qw(SOAP::Transport::HTTP::Daemon::ThreadOnAccept);
#@ISA = qw(SOAP::Transport::HTTP::Daemon);

# request() is the only method that needs overloading in order for
# this Daemon class to handle the authentication. All cookie headers
# on the incoming request get copied to a hash table local to the
# eSTAR::NA::SOAP::Handler package. The request is then passed on
# to the original version of this method.

sub request {
  my $self = shift;
  
  if ( my $request = $_[0] ) {         
    my @cookies = $request->headers()->header('cookie');
    %eSTAR::RAPTOR::SOAP::Handler::COOKIES = ();
    for my $line (@cookies) {
       for ( split(/; /, $line)) {
          next unless /(.*?)=(.*)/;
          $eSTAR::RAPTOR::SOAP::Handler::COOKIES{$1} = $2;
       }   
    }
  }

  $self->SUPER::request(@_);
}

1;
