package eSTAR::Logging;

# ---------------------------------------------------------------------------

#+ 
#  Name:
#    eSTAR::Running

#  Purposes:
#    Perl object to handling the running observations hash for the JACH

#  Language:
#    Perl module

#  Description:
#    This module which handles the %running observations

#  Authors:
#    Alasdair Allan (aa@astro.ex.ac.uk)

#  Revision:
#     $Id: Running.pm,v 1.2 2004/11/05 15:32:09 aa Exp $

#  Copyright:
#     Copyright (C) 2001 University of Exeter. All Rights Reserved.

#-

# ---------------------------------------------------------------------------

=head1 NAME

eSTAR::Running - Object to handle running observations

=head1 SYNOPSIS

  $object = eSTAR::Running::get_reference();
  $object->set_hash( %hash );
  my %hash = $object->get_hash();

=head1 DESCRIPTION

Handles running

=cut

# L O A D   M O D U L E S --------------------------------------------------

use strict;
use vars qw/ $VERSION /;
use subs qw/ new set_hash get_hash /;

use threads;
use threads::shared;

use eSTAR::Error qw /:try/;
use eSTAR::Constants qw /:status/;

'$Revision: 1.2 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

# C O N S T R U C T O R ----------------------------------------------------

# is a single instance class, can only be once instance for the entire
# application. Use get_reference() to grab a reference to the object.
my $SINGLETON;

sub new {
  return $SINGLETON if defined $SINGLETON;

  my $proto = shift;
  my $class = ref($proto) || $proto;

  # bless the query hash into the class
  $SINGLETON = bless { PROCESS      => undef,
                       TAGNUM       => undef,
                       RUNNING_HASH => undef }, $class;
  
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
 
  # UNIQUE TAG NUMBER
  # -----------------

  # Tag number identifying each individual instance of the class
  my $tagid = sprintf( '%.0f', rand( 1000 ) );
  $self->{TAGNUM} = "TagID#" . $self->{PROCESS} . "#$tagid";

}

# M E T H O D S -----------------------------------------------------------

=head1 REVISION

$Id: Running.pm,v 1.2 2004/11/05 15:32:09 aa Exp $

=head1 METHODS

The following methods are available from this module:

=over 4

=item B<set_hash>

Store a reference to the current running hash

  $object->set_hash( %hash );

=cut

sub set_hash {
  my $self = shift;
  my %hash = $@;
   
  $self->{RUNNING_HASH} = \%hash; 
  
}     

=item B<get_hash>

Retreieve a reference to the current running hash

  my %hash = $object->get_hash();

=cut

sub get_hash {
  my $self = shift;
   
  return %$self->{RUNNING_HASH}; 
  
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
