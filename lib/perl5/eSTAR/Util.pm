package eSTAR::Util;

=head1 NAME

eSTAR::Util - utility routines

=head1 SYNOPSIS

  use eSTAR::Util
  
  make_cookie()
  
=head1 DESCRIPTION

This module contains a simple utility routine for cookie generation.

=cut

use strict;
use warnings;

require Exporter;

use vars qw/$VERSION @EXPORT @ISA /;

use Digest::MD5 'md5_hex';

@ISA = qw/Exporter/;
@EXPORT = qw/make_cookie/;

'$Revision: 1.2 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

# This is the code that is used to generate cookies based on the user
# name and password. It is NOT cryptographically sound, it is just a
# simple form of obfuscation, used as an example. Should be replaced
# before system goes live. (AA 06-MAY-2003)
sub make_cookie {
   my ($user, $passwd) = @_;
   my $cookie = $user . "::" . md5_hex($passwd);
   $cookie =~ s/(.)/sprintf("%%%02x", ord($1))/ge;
   $cookie =~ s/%/%25/g;
   $cookie;
}

=back

=head1 REVISION

$Id: Util.pm,v 1.2 2004/02/20 00:42:29 aa Exp $

=head1 AUTHORS

Alasdair Allan E<lt>aa@astro.ex.ac.ukE<gt>

=head1 COPYRIGHT

Copyright (C) 2003 Particle Physics and Astronomy Research
Council. All Rights Reserved.

=cut

1;
