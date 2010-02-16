package Business::OnlinePayment::Litle;

use warnings;
use strict;

use Business::OnlinePayment;
use Business::OnlinePayment::HTTPS;
use vars qw(@ISA $me $DEBUG $VERSION);
use XML::Writer;
use Tie::IxHash;
use Data::Dumper;

@ISA = qw(Business::OnlinePayment::HTTPS);
$me = 'Business::OnlinePayment::Litle';
$DEBUG = 1;
$VERSION = '0.01';

=head1 NAME

Business::OnlinePayment::Litle - Litle & Co. Backend for Business::OnlinePayment

=head1 VERSION

Version 0.01

=cut


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
    my %opts = @_;

    $self->server('jaycehall.com') unless $self->server;
    $self->port('443') unless $self->port;
    $self->path('/somewhere/to/post') unless $self->path;

    if ( $opts{debug} ) {
        $self->debug( $opts{debug} );
        delete $opts{debug};
    }

    ## load in the defaults
    my %_defaults = ();
    foreach my $key (keys %opts) {
        $key =~ /^default_(\w*)$/ or next;
        $_defaults{$1} = $opts{$key};
        delete $opts{$key};
    }

    $self->build_subs(qw( order_number md5 avs_code cvv2_response
                          cavv_response api_version xmlns
                     ));

    $self->api_version('7.2') unless $self->api_version;
    $self->xmlns('http://www.litle.com/schema') unless $self->xmlns;
}

=head2 map_fields

=cut

sub map_fields {
    my($self) = @_;

    my %content = $self->content();

    my $action = lc($content{'action'});
    my %actions = (
        'normal authorization'      =>  'sale',
        'authorization only'        =>  'authorization',
        'post authorization'        =>  'capture',
        'void'                      =>  'void',
        'credit'                    =>  'credit',
        # AVS ONLY
        # Capture Given
        # Force Capture
        #
    );
    $content{'TransactionType'} = $actions{$action} || $action;

        
    if ($content{recurring_billing} && $content{recurring_billing} eq 'YES' ){
        $content{'orderSource'} = 'recurring';
    } else {
        $content{'orderSource'} = 'ecommerce';
    }
    $content{'customerType'} =  $content{'orderSource'} eq 'recurring' ? 'E' : 'N'; # new/Existing


    $content{'deliverytype'} = 'SVC';
    # stuff it back into %content
    if( $content{'products'} && ref( $content{'products'} ) eq 'ARRAY' ){
        my $count = 1;
        foreach ( @{ $content{'products'} }){
            $_->{'itemSequenceNumber'} = $count++;
        }
    }
    $self->content(%content);
}

sub submit {
    my ($self) = @_;

    $self->is_success(0);
    $self->map_fields;
    my %content = $self->content();


    my $post_data;
    my $writer = new XML::Writer( OUTPUT        => \$post_data,
                                  DATA_MODE     => 1,
                                  DATA_INDENT   => 2,
                                  ENCODING      => 'utf8',
                              );

    # for tabbing
    # clean up the amount to the required format
    my $amount;
    if (defined($content{amount})) {
        $amount = sprintf("%.2f",$content{amount});
        $amount =~ s/\.//g;
    }


    tie my %billToAddress, 'Tie::IxHash', 
    $self->revmap_fields(
        name            =>  'name',
        email           =>  'email',
        addressLine1    =>  'address',
        city            =>  'city',
        state           =>  'state',
        zip             =>  'zip',
        country         =>  'country',  #TODO: will require validation to the spec, this field wont' work as is
        email           =>  'email',
        phone           =>  'phone',
    );

    tie my %authentication, 'Tie::IxHash', 
    $self->revmap_fields(
        user    =>  'login',
        password    =>  'password',
    );

    tie my %customerinfo, 'Tie::IxHash', 
    $self->revmap_fields(
        customerType    =>  'customerType',
    );

    tie my %custombilling, 'Tie::IxHash', 
    $self->revmap_fields(
        descriptor  =>  'description',
        url         =>  'url',
        phone       =>  'company_phone',
    );

    ## loop through product list and generate linItemData for each
    tie my %enhanceddata, 'Tie::IxHash', 
    $self->revmap_fields(
            orderDate   =>  'orderdate',
            salesTax    =>  'salestax',
            invoiceReferenceNumber  =>  'invoice_number', ##
            deliveryType    =>  'deliverytype',
            customerReference   =>  'po_number',
            lineItemData    =>  $content{'products'},
    );

    tie my %req, 'Tie::IxHash', 
        $self->revmap_fields(
            orderID     =>  'invoice_number',
            card        =>  'card_number',
            orderSource =>  'orderSource',
            amount      =>  \$amount,
            billToAddress   =>  \%billToAddress,
            authentication  => \%authentication,
            customerInfo    =>  \%customerinfo,
            customBilling   =>  \%custombilling,
            enhancedData    =>  \%enhanceddata,
        );


        warn Dumper( \%req ) if $DEBUG;
    ## Start the XML Document, parent tag
    $writer->xmlDecl();
    $writer->startTag("litleOnlineRequest",
        version => $self->api_version,
        xmlns => $self->xmlns,
        merchantId => 'someaccount'
    );

    foreach ( keys ( %req ) ) { 
        $self->_xmlwrite($writer, $_, $req{$_});
    }

    $writer->endTag("litleOnlineRequest");
    $writer->end();
    ## END XML Generation

    warn "$post_data\n" if $DEBUG;

    my ($page,$server_response,%headers) = $self->https_post($post_data);

    warn "$page\n" if $DEBUG;
}

sub revmap_fields {
  my $self = shift;
  tie my(%map), 'Tie::IxHash', @_;
  my %content = $self->content();
  map {
        my $value;
        if ( ref( $map{$_} ) eq 'HASH' ) {
          $value = $map{$_} if ( keys %{ $map{$_} } );
        }elsif ( ref( $map{$_} ) eq 'ARRAY' ) {
          $value = $map{$_};
        }elsif( ref( $map{$_} ) ) {
          $value = ${ $map{$_} };
        }elsif( exists( $content{ $map{$_} } ) ) {
          $value = $content{ $map{$_} };
        }

        if (defined($value)) {
          ($_ => $value);
        }else{
          ();
        }
      } (keys %map);
}

sub _xmlwrite {
    my ($self, $writer, $item, $value) = @_;
    if ( ref( $value ) eq 'HASH' ) {
        my $attr =   $value->{'attr'} ? $value->{'attr'} : {};
        $writer->startTag($item, %{ $attr });
        foreach ( keys ( %$value ) ) {
            next if $_ eq 'attr';
            $self->_xmlwrite($writer, $_, $value->{$_});
        }
        $writer->endTag($item);
    }elsif ( ref( $value ) eq 'ARRAY' ) {
        foreach ( @{ $value } ) {
            $self->_xmlwrite($writer, $item, $_);
        }
    }else{
        $writer->startTag($item);
        $writer->characters($value);
        $writer->endTag($item);
    }
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
