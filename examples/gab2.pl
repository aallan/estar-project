#!/usr/bin/perl

# gab2.pl - A simple forking TCP network client.
# This code closely based on an example from "Network Programming in Perl" by
# Lincoln D. Stein.
# Eric Saunders, January 2007.

use strict;
use warnings;

use IO::Socket qw(:DEFAULT :crlf);

my $host = 'localhost';
my $port = shift || '6666';

my $socket = IO::Socket::INET->new("$host:$port") or die $@;
my $child = fork;
die "Can't fork: $!" unless defined $child;

if ( $child ) {
   $SIG{CHLD} = sub {exit 0};
   user_to_host($socket);
   $socket->shutdown(1);
   sleep;
}
else {
   host_to_user($socket);
   warn "Connection closed by foreign host.\n";
}

sub user_to_host {
   my $socket = shift;
   while ( <> ) {
      chomp;
      print $socket $_, CRLF;
   }

   return;
}

sub host_to_user {
   my $socket = shift;
   $/ = CRLF;
   while ( <$socket> ) {
      chomp;
      print $_, "\n";
   }
   
   return;
}
