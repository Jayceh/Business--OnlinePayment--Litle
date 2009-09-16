package Business::OnlinePayment::Litle;

use warnings;
use strict;

use Business::OnlinePayment;
use vars qw(@ISA $me);

@ISA = qw(Business::OnlinePayment);
$me = 'Business::OnlinePayment::Litle';

=head1 NAME

Business::OnlinePayment::Litle - Litle & Co. Backend for Business::OnlinePayment

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Business::OnlinePayment::Litle;

    my $foo = Business::OnlinePayment::Litle->new();
    ...

=head1 FUNCTIONS

=head2 set_defaults

=cut

sub set_defaults {
    my $self = shift;

    $self->server('secure.litle.com') unless $self->server;
    $self->port('443') unless $self->port;
    $self->path('/gateway/transact.dll') unless $self->path;

    $self->build_subs(qw( order_number md5 avs_code cvv2_response
                          cavv_response
                     ));
}

=head2 map_fields

=cut

sub map_fields {
    my($self) = @_;

    my %content = $self->content();

    # stuff it back into %content
    $self->content(%content);
}

=head1 AUTHOR

Jason Hall, C<< <jayce at lug-nut.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-business-onlinepayment-litle at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Business-OnlinePayment-Litle>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Business::OnlinePayment::Litle


You can also look for information at:

L<http://www.litle.com/>

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Business-OnlinePayment-Litle>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Business-OnlinePayment-Litle>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Business-OnlinePayment-Litle>

=item * Search CPAN

L<http://search.cpan.org/dist/Business-OnlinePayment-Litle/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2009 Jason Hall.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.
=back


=head1 SEE ALSO

perl(1). L<Business::OnlinePayment>


=cut

1; # End of Business::OnlinePayment::Litle
