package eSTAR::UserAgent;

=head1 NAME

eSTAR::Process - wrapper object to hold an LWP::UserAgent object

=head1 SYNOPSIS

  use eSTAR::UserAgent
  
  my $ua = new eSTAR::UserAgent( $user_agent );
  $ua = eSTAR::UserAgent::get_reference();
  
  $ua->set_ua( $user_agent )
  my $user_agent = $ua->get_ua()
 
  
=head1 DESCRIPTION

This module contains simple wrapped routines to hold an LWP::UserAgent. 
This is a single instance object.

=cut

use strict;
use warnings;

require Exporter;

use vars qw/$VERSION @EXPORT @ISA/;

@ISA = qw/Exporter/;
@EXPORT = qw/set_ua get_ua/;

'$Revision: 1.2 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

my $SINGLETON;

sub new {
   return $SINGLETON if defined $SINGLETON;

   my $proto = shift;
   my $class = ref($proto) || $proto;   
   $SINGLETON = bless { UA => undef, }, $class;
   
   $SINGLETON->set_ua( @_ ) if defined @_;
   return $SINGLETON;
}

sub get_reference {
  return $SINGLETON if defined $SINGLETON;
  return undef;
}

sub set_ua {
   my $self = shift;
   $self->{UA} = shift;   
}

sub get_ua {
   my $self = shift;
   return $self->{UA};
}   


=back

=head1 REVISION

$Id: UserAgent.pm,v 1.2 2004/12/21 17:10:19 aa Exp $

=head1 AUTHORS

Alasdair Allan E<lt>aa@astro.ex.ac.ukE<gt>

=head1 COPYRIGHT

Copyright (C) 2003 Particle Physics and Astronomy Research
Council. All Rights Reserved.

=cut

1;
