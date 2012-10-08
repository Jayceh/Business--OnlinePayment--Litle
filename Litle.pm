package Business::OnlinePayment::Litle;

use warnings;
use strict;

use Business::OnlinePayment;
use Business::OnlinePayment::HTTPS;
use Business::OnlinePayment::Litle::ErrorCodes '%ERRORS';
use vars qw(@ISA $me $DEBUG $VERSION);
use MIME::Base64;
use HTTP::Tiny;
use XML::Writer;
use XML::Simple;
use Tie::IxHash;
use Business::CreditCard qw(cardtype);
use Data::Dumper;
use IO::String;
use Carp qw(croak);
use Log::Scrubber qw(disable $SCRUBBER scrubber :Carp);

@ISA     = qw(Business::OnlinePayment::HTTPS);
$me      = 'Business::OnlinePayment::Litle';
$DEBUG   = 0;
$VERSION = '0.932';

=head1 NAME

Business::OnlinePayment::Litle - Litle & Co. Backend for Business::OnlinePayment

=head1 VERSION

Version 0.932

=cut

=head1 SYNOPSIS

This is a plugin for the Business::OnlinePayment interface.  Please refer to that docuementation for general usage, and here for Litle specific usage.

In order to use this module, you will need to have an account set up with Litle & Co. L<http://www.litle.com/>


  use Business::OnlinePayment;
  my $tx = Business::OnlinePayment->new(
     "Litle",
     default_Origin => 'NEW',
  );

  $tx->content(
      type           => 'CC',
      login          => 'testdrive',
      password       => '123qwe',
      action         => 'Normal Authorization',
      description    => 'FOO*Business::OnlinePayment test',
      amount         => '49.95',
      customer_id    => 'tfb',
      name           => 'Tofu Beast',
      address        => '123 Anystreet',
      city           => 'Anywhere',
      state          => 'UT',
      zip            => '84058',
      card_number    => '4007000000027',
      expiration     => '09/02',
      cvv2           => '1234', #optional
      invoice_number => '54123',
  );
  $tx->submit();

  if($tx->is_success()) {
      print "Card processed successfully: ".$tx->authorization."\n";
  } else {
      print "Card was rejected: ".$tx->error_message."\n";
  }

=head1 METHODS AND FUNCTIONS

See L<Business::OnlinePayment> for the complete list. The following methods either override the methods in L<Business::OnlinePayment> or provide additional functions.

=head2 result_code

Returns the response error code.

=head2 error_message

Returns the response error description text.

=head2 server_request

Returns the complete request that was sent to the server.  The request has been stripped of card_num, cvv2, and password.  So it should be safe to log.

=head2 server_response

Returns the complete response from the server.  The response has been stripped of card_num, cvv2, and password.  So it should be safe to log.

=head1 Handling of content(%content) data:

=head2 action

The following actions are valid

  normal authorization
  authorization only
  post authorization
  credit
  void

=head1 Litle specific data

=head2 Fields

Most data fields not part of the BOP standard can be added to the content hash directly, and will be used

Most data fields will truncate extra characters to conform to the Litle XML length requirements.  Some fields (mostly amount fields) will error if your data exceeds the allowed length.

=head2 Products

Part of the enhanced data for level III Interchange rates

    products        =>  [
    {   description =>  'First Product',
        sku         =>  'sku',
        quantity    =>  1,
        units       =>  'Months'
        amount      =>  '5.00',
        discount    =>  0,
        code        =>  1,
        cost        =>  '5.00',
    },
    {   description =>  'Second Product',
        sku         =>  'sku',
        quantity    =>  1,
        units       =>  'Months',
        amount      =>  1500,
        discount    =>  0,
        code        =>  2,
        cost        =>  '5.00',
    }

    ],

=cut

=head1 SPECS

Currently uses the Litle XML specifications version 8.12 and chargeback version 2.2

=head1 TESTING

In order to run the provided test suite, you will first need to apply and get your account setup with Litle.  Then you can use the test account information they give you to run the test suite. The scripts will look for three environment variables to connect: BOP_USERNAME, BOP_PASSWORD, BOP_MERCHANTID

Currently the description field also uses a fixed descriptor.  This will possibly need to be changed based on your arrangements with Litle.

=head1 FUNCTIONS

=head2 _info

Return the introspection hash for BOP 3.x

=cut

sub _info {
    return {
        info_compat       => '0.01',
        gateway_name      => 'Litle',
        gateway_url       => 'http://www.litle.com',
        module_version    => $VERSION,
        supported_types   => ['CC'],
        supported_actions => {
            CC => [
                'Normal Authorization',
                'Post Authorization',
                'Authorization Only',
                'Credit',
                'Void',
                'Auth Reversal',
            ],
        },
    };
}

=head2 set_defaults

=cut

sub set_defaults {
    my $self = shift;
    my %opts = @_;

    $self->build_subs(
        qw( order_number md5 avs_code cvv2_response
          cavv_response api_version xmlns failure_status batch_api_version chargeback_api_version
          is_prepaid prepaid_balance get_affluence chargeback_server chargeback_port chargeback_path
          verify_SSL phoenixTxnId server_request server_response
          )
    );

    $self->test_transaction(0);

    if ( $opts{debug} ) {
        $self->debug( $opts{debug} );
        delete $opts{debug};
    }

    ## load in the defaults
    my %_defaults = ();
    foreach my $key ( keys %opts ) {
        $key =~ /^default_(\w*)$/ or next;
        $_defaults{$1} = $opts{$key};
        delete $opts{$key};
    }

    $self->api_version('8.1')                   unless $self->api_version;
    $self->batch_api_version('8.1')             unless $self->batch_api_version;
    $self->chargeback_api_version('2.2')        unless $self->chargeback_api_version;
    $self->xmlns('http://www.litle.com/schema') unless $self->xmlns;
}

=head2 test_transaction

Get/set the server used for processing transactions.  Possible values are Live, Certification, and Sandbox
Default: Live

  #Live
  $self->test_transaction(0);

  #Certification
  $self->test_transaction(1);

  #Sandbox
  $self->test_transaction('sandbox');

  #Read current value
  $val = $self->test_transaction();

=cut

sub test_transaction {
    my $self = shift;
    my $testMode = shift;
    if (! defined $testMode) { $testMode = $self->{'test_transaction'} || 0; }

    if (lc($testMode) eq 'sandbox') {
    $self->{'test_transaction'} = 'sandbox';
        $self->verify_SSL(0);

        $self->server('www.testlitle.com');
        $self->port('443');
        $self->path('/sandbox/communicator/online');

        $self->chargeback_server('services.cert.litle.com'); # no sandbox exists, so fallback to certify
        $self->chargeback_port('443');
        $self->chargeback_path('/services/communicator/chargebacks/webCommunicator');
    } elsif (lc($testMode) eq 'localhost') {
        # this allows the user to create a local web server to do generic testing with
    $self->{'test_transaction'} = 'localhost';
        $self->verify_SSL(0);

        $self->server('localhost');
        $self->port('443');
        $self->path('/sandbox/communicator/online');

        $self->chargeback_server('localhost');
        $self->chargeback_port('443');
        $self->chargeback_path('/services/communicator/chargebacks/webCommunicator');
    } elsif ($testMode) {
    $self->{'test_transaction'} = $testMode;
        $self->verify_SSL(0);

        $self->server('cert.litle.com');
        $self->port('443');
        $self->path('/vap/communicator/online');

        $self->chargeback_server('services.cert.litle.com');
        $self->chargeback_port('443');
        $self->chargeback_path('/services/communicator/chargebacks/webCommunicator');
    } else {
    $self->{'test_transaction'} = 0;
        $self->verify_SSL(1);

        $self->server('payments.litle.com');
        $self->port('443');
        $self->path('/vap/communicator/online');

        $self->chargeback_server('services.litle.com');
        $self->chargeback_port('443');
        $self->chargeback_path('/services/communicator/chargebacks/webCommunicator');
    }

    return $self->{'test_transaction'};
}

=head2 map_fields

=cut

sub map_fields {
    my ( $self, $content ) = @_;

    local $SCRUBBER=1;
    $self->_litle_scrubber_init;

    my $action  = lc( $content->{'action'} );
    my %actions = (
        'normal authorization' => 'sale',
        'authorization only'   => 'authorization',
        'post authorization'   => 'capture',
        'void'                 => 'void',
        'credit'               => 'credit',
        'auth reversal'        => 'authReversal',
        'account update'       => 'accountUpdate',

        # AVS ONLY
        # Capture Given
        # Force Capture
        #
    );
    $content->{'TransactionType'} = $actions{$action} || $action;

    my $type_translate = {
        'VISA card'                   => 'VI',
        'MasterCard'                  => 'MC',
        'Discover card'               => 'DI',
        'American Express card'       => 'AX',
        'Diner\'s Club/Carte Blanche' => 'DI',
        'JCB'                         => 'DI',
        'China Union Pay'             => 'DI',
    };

    $content->{'card_type'} =
         $type_translate->{ cardtype( $content->{'card_number'} ) }
      || $content->{'type'};

    if (   $content->{recurring_billing}
        && $content->{recurring_billing} eq 'YES' )
    {
        $content->{'orderSource'} = 'recurring';
    }
    else {
        $content->{'orderSource'} = 'ecommerce';
    }
    $content->{'customerType'} =
      $content->{'orderSource'} eq 'recurring'
      ? 'Existing'
      : 'New';    # new/Existing

    $content->{'deliverytype'} = 'SVC';

    # stuff it back into %content
    if ( $content->{'products'} && ref( $content->{'products'} ) eq 'ARRAY' ) {
        my $count = 1;
        foreach ( @{ $content->{'products'} } ) {
            $_->{'itemSequenceNumber'} = $count++;
        }
    }

    if( $content->{'velocity_check'} && (
        $content->{'velocity_check'} != 0
        && $content->{'velocity_check'} !~ m/false/i ) ) {
      $content->{'velocity_check'} = 'true';
    } else {
      $content->{'velocity_check'} = 'false';
    }

    if( $content->{'partial_auth'} && (
        $content->{'partial_auth'} != 0
        && $content->{'partial_auth'} !~ m/false/i ) ) {
      $content->{'partial_auth'} = 'true';
    } else {
      $content->{'partial_auth'} = 'false';
    }

    $self->content( %{$content} );
    return $content;
}

=head2 format_misc_field

Used internally to guarentee that XML data will conform to the Litle spec.
  maxLen - The maximum length allowed (extra bytes will be truncated)
  minLen - The minimum length allowed
  errorOnLength - boolean
    0 - truncate any extra bytes
    1 - error if the length is out of bounds
  isRequired - boolean
    0 - ignore undefined values
    1 - error if the value is not defined

 $tx->format_misc_field( \%content, [field, maxLen, minLen, errorOnLength, isRequired] );
 $tx->format_misc_field( \%content, ['amount',   0,     12,             0,          0] );

=cut

sub format_misc_field {
    my ($self, $content, $trunc) = @_;

    local $SCRUBBER=1;
    $self->_litle_scrubber_init;

    use bytes; # make sure we truncate on bytes, not characters

    if( defined $content->{ $trunc->[0] } ) {
      my $len = bytes::length( $content->{ $trunc->[0] } );
      if ( $trunc->[3] && $trunc->[2] && $len != 0 && $len < $trunc->[2] ) {
        # Zero is a valid length (mostly for cvv2 value)
        croak "$trunc->[0] has too few characters";
      }
      elsif ( $trunc->[3] && $trunc->[1] && $len > $trunc->[1] ) {
        croak "$trunc->[0] has too many characters";
      }
      $content->{ $trunc->[0] } = bytes::substr($content->{ $trunc->[0] } , 0, $trunc->[1] );
      #warn "$trunc->[0] => $len => $content->{ $trunc->[0] }\n" if $DEBUG;
    }
    elsif ( $trunc->[4] ) {
      croak "$trunc->[0] is required";
    }
}

=head2 format_amount_field

Used internally to change amounts from the BOP "5.00" format to the format expected by Litle "500"

$tx->format_amount_field( \%content, 'amount' );

=cut

sub format_amount_field {
    my ($self, $data, $field) = @_;
    if (defined ( $data->{$field} ) ) {
        $data->{$field} = sprintf( "%.2f", $data->{$field} );
        $data->{$field} =~ s/\.//g;
    }
}

=head2 format_phone_field

Used internally to strip invalid characters from phone numbers. IE "1 (800).TRY-THIS" becomes "18008788447"

$tx->format_phone_field( \%content, 'company_phone' );

=cut

sub format_phone_field {
    my ($self, $data, $field) = @_;
    if (defined ( $data->{$field} ) ) {
        my $convertPhone = {
            'a' => 2, 'b' => 2, 'c' => 2,
            'd' => 3, 'e' => 3, 'f' => 3,
            'g' => 4, 'h' => 4, 'i' => 4,
            'j' => 5, 'k' => 5, 'l' => 5,
            'm' => 6, 'n' => 6, 'o' => 6,
            'p' => 7, 'q' => 7, 'r' => 7, 's' => 7,
            't' => 8, 'u' => 8, 'v' => 8,
            'w' => 9, 'x' => 9, 'y' => 9, 'z' => 9,
        };
        $data->{$field} =~ s/(\D)/$$convertPhone{lc($1)}||''/eg;
    }
}

sub map_request {
    my ( $self, $content ) = @_;

    local $SCRUBBER=1;
    $self->_litle_scrubber_init;

    $self->map_fields($content);

    my $action = $content->{'TransactionType'};

    my @required_fields = qw(action type);

    $self->required_fields(@required_fields);

    # for tabbing
    # set dollar amounts to the required format (eg $5.00 should be 500)
    foreach my $field ( 'amount', 'salesTax', 'discountAmount', 'shippingAmount', 'dutyAmount' ) {
        $self->format_amount_field($content, $field);
    }

    # make sure the date is in MMYY format
    $content->{'expiration'} =~ s/^(\d{1,2})\D*\d*?(\d{2})$/$1$2/;

    if ( ! defined $content->{'description'} ) { $content->{'description'} = ''; } # shema req
    $content->{'description'} =~ s/[^\w\s\*\,\-\'\#\&\.]//g;

    # only numbers are allowed in company_phone
    $self->format_phone_field($content, 'company_phone');

    #  put in a list of constraints
    my @validate = (
      # field,     maxLen, minLen, errorOnLength, isRequired
      [ 'name',       100,      0,             0, 0 ],
      [ 'email',      100,      0,             0, 0 ],
      [ 'address',     35,      0,             0, 0 ],
      [ 'city',        35,      0,             0, 0 ],
      [ 'state',       30,      0,             0, 0 ], # 30 is allowed, but it should be the 2 char code
      [ 'zip',         20,      0,             0, 0 ],
      [ 'country',      3,      0,             0, 0 ], # should use iso 3166-1 2 char code
      [ 'phone',       20,      0,             0, 0 ],

      [ 'ship_name',  100,      0,             0, 0 ],
      [ 'ship_email', 100,      0,             0, 0 ],
      [ 'ship_address',35,      0,             0, 0 ],
      [ 'ship_city',   35,      0,             0, 0 ],
      [ 'ship_state',  30,      0,             0, 0 ], # 30 is allowed, but it should be the 2 char code
      [ 'ship_zip',    20,      0,             0, 0 ],
      [ 'ship_country', 3,      0,             0, 0 ], # should use iso 3166-1 2 char code
      [ 'ship_phone',  20,      0,             0, 0 ],

      #[ 'customerType',13,      0,             0, 0 ],

      ['company_phone',13,      0,             0, 0 ],
      [ 'description', 25,      0,             0, 0 ],

      [ 'po_number',   17,      0,             0, 0 ],
      [ 'salestax',     8,      0,             1, 0 ],
      [ 'discount',     8,      0,             1, 0 ],
      [ 'shipping',     8,      0,             1, 0 ],
      [ 'duty',         8,      0,             1, 0 ],
      ['invoice_number',15,     0,             0, 0 ], # TODO orderID = 25, invoiceReferenceNumber = 15
      [ 'orderdate',   10,      0,             0, 0 ], # YYYY-MM-DD

      [ 'recycle_by',   8,      0,             0, 0 ],
      [ 'recycle_id',  25,      0,             0, 0 ],

      [ 'affiliate',   25,      0,             0, 0 ],

      [ 'card_type',    2,      2,             1, 0 ],
      [ 'card_number', 25,     13,             1, 0 ],
      [ 'expiration',   4,      4,             1, 0 ], # MMYY
      [ 'cvv2',         4,      3,             1, 0 ],
      # 'token' does not have a documented limit

      [ 'customer_id', 25,      0,             0, 0 ],
    );
    foreach my $trunc ( @validate ) {
      $self->format_misc_field($content,$trunc);
      #warn "$trunc->[0] => ".($content->{ $trunc->[0] }||'')."\n" if $DEBUG;
    }

    tie my %billToAddress, 'Tie::IxHash', $self->revmap_fields(
        content      => $content,
        name         => 'name',
        email        => 'email',
        addressLine1 => 'address',
        city         => 'city',
        state        => 'state',
        zip          => 'zip',
        country      => 'country'
        , #TODO: will require validation to the spec, this field wont' work as is
        phone => 'phone',
    );

    tie my %shipToAddress, 'Tie::IxHash', $self->revmap_fields(
        content      => $content,
        name         => 'ship_name',
        email        => 'ship_email',
        addressLine1 => 'ship_address',
        city         => 'ship_city',
        state        => 'ship_state',
        zip          => 'ship_zip',
        country      => 'ship_country'
        , #TODO: will require validation to the spec, this field wont' work as is
        phone => 'ship_phone',
    );

    tie my %customerinfo, 'Tie::IxHash',
      $self->revmap_fields(
        content      => $content,
        customerType => 'customerType',
      );

    tie my %custombilling, 'Tie::IxHash',
      $self->revmap_fields(
        content      => $content,
        phone      => 'company_phone',
        descriptor => 'description',
      );

    ## loop through product list and generate linItemData for each
    #
    my @products = ();
    if( defined $content->{'products'} && scalar( @{ $content->{'products'} } ) < 100 ){
      foreach my $prodOrig ( @{ $content->{'products'} } ) {
          # use a local copy of prod so that we do not have issues if they try to submit more then once.
          my %prod = %$prodOrig;
          foreach my $field ( 'tax','amount','totalwithtax','discount' ) {
            # Note: DO NOT format 'cost', it uses the decimal format
            $self->format_amount_field(\%prod, $field);
          }

          my @validate = (
            # field,     maxLen, minLen, errorOnLength, isRequired
            [ 'description', 26,      0,             0, 0 ],
            [ 'tax',          8,      0,             1, 0 ],
            [ 'amount',       8,      0,             1, 0 ],
            [ 'totalwithtax', 8,      0,             1, 0 ],
            [ 'discount',     8,      0,             1, 0 ],
            [ 'code',        12,      0,             0, 0 ],
            [ 'cost',        12,      0,             1, 0 ],
          );
          foreach my $trunc ( @validate ) { $self->format_misc_field(\%prod,$trunc); }

          tie my %lineitem, 'Tie::IxHash',
            $self->revmap_fields(
              content              => \%prod,
              itemSequenceNumber   => 'itemSequenceNumber',
              itemDescription      => 'description',
              productCode          => 'code',
              quantity             => 'quantity',
              unitOfMeasure        => 'units',
              taxAmount            => 'tax',
              lineItemTotal        => 'amount',
              lineItemTotalWithTax => 'totalwithtax',
              itemDiscountAmount   => 'discount',
              commodityCode        => 'code',
              unitCost             => 'cost', # This "amount" field uses decimals
            );
          push @products, \%lineitem;
      }
    }

    #
    #
    tie my %enhanceddata, 'Tie::IxHash', $self->revmap_fields(
        content                => $content,
        customerReference      => 'po_number',
        salesTax               => 'salestax',
        discountAmount         => 'discount',
        shippingAmount         => 'shipping',
        dutyAmount             => 'duty',
        invoiceReferenceNumber => 'invoice_number',    ##
        orderDate              => 'orderdate',
        lineItemData           => \@products,
    );

    tie my %card, 'Tie::IxHash', $self->revmap_fields(
        content            => $content,
        type               => 'card_type',
        number             => 'card_number',
        expDate            => 'expiration',
        cardValidationNum  => 'cvv2',
    );

    tie my %token, 'Tie::IxHash', $self->revmap_fields(
        content            => $content,
        litleToken         => 'token',
        expDate            => 'expiration',
        cardValidationNum  => 'cvv2',
    );

    tie my %processing, 'Tie::IxHash', $self->revmap_fields(
        content               => $content,
        bypassVelocityCheck   => 'velocity_check',
    );

    tie my %cardholderauth, 'Tie::IxHash',
      $self->revmap_fields(
        content                     => $content,
        authenticationValue         => '3ds',
        authenticationTransactionId => 'visaverified',
        customerIpAddress           => 'ip',
        authenticatedByMerchant     => 'authenticated',
      );

    tie my %merchantdata, 'Tie::IxHash',
      $self->revmap_fields(
        content      => $content,
        affiliate    => 'affiliate',
      );

    tie my %recyclingrequest, 'Tie::IxHash',
      $self->revmap_fields(
        content      => $content,
        recycleBy    => 'recycle_by',
        recycleId    => 'recycle_id',
      );

    my %req;

    if ( $action eq 'sale' ) {
        tie %req, 'Tie::IxHash', $self->revmap_fields(
            content       => $content,
            orderId       => 'invoice_number',
            amount        => 'amount',
            orderSource   => 'orderSource',
            billToAddress => \%billToAddress,
            card          => \%card,
            token         => $content->{'token'} ? \%token : {},

            #cardholderAuthentication    =>  \%cardholderauth,
            customBilling => \%custombilling,
            enhancedData  => \%enhanceddata,
            processingInstructions  =>  \%processing,
            allowPartialAuth => 'partial_auth',
            merchantData => \%merchantdata,
            recyclingRequest => \%recyclingrequest,
        );
    }
    elsif ( $action eq 'authorization' ) {
        tie %req, 'Tie::IxHash', $self->revmap_fields(
            content       => $content,
            orderId       => 'invoice_number',
            amount        => 'amount',
            orderSource   => 'orderSource',
            billToAddress => \%billToAddress,
            card          => \%card,
            token         => $content->{'token'} ? \%token : {},

            #cardholderAuthentication    =>  \%cardholderauth,
            processingInstructions  =>  \%processing,
            customBilling => \%custombilling,
            allowPartialAuth => 'partial_auth',
            merchantData     => \%merchantdata,
            recyclingRequest => \%recyclingrequest,
        );
    }
    elsif ( $action eq 'capture' ) {
        push @required_fields, qw( order_number amount );
        tie %req, 'Tie::IxHash',
          $self->revmap_fields(
            content      => $content,
            litleTxnId   => 'order_number',
            amount       => 'amount',
            enhancedData => \%enhanceddata,
            processingInstructions => \%processing,
          );
    }
    elsif ( $action eq 'credit' ) {

       # IF there is a litleTxnId, it's a normal linked credit
       if( $content->{'order_number'} ){
          push @required_fields, qw( order_number amount );
          tie %req, 'Tie::IxHash', $self->revmap_fields(
              content       => $content,
              litleTxnId    => 'order_number',
              amount        => 'amount',
              customBilling => \%custombilling,
              processingInstructions => \%processing,
          );
        }
       # ELSE it's an unlinked, which requires different data
       else {
          push @required_fields, qw( invoice_number amount );
          tie %req, 'Tie::IxHash', $self->revmap_fields(
              content       => $content,
              orderId       => 'invoice_number',
              amount        => 'amount',
              orderSource   => 'orderSource',
              billToAddress => \%billToAddress,
              card          => \%card,
              token         => $content->{'token'} ? \%token : {},
              customBilling => \%custombilling,
              processingInstructions => \%processing,
          );
       }
    }
    elsif ( $action eq 'void' ) {
        push @required_fields, qw( order_number );
        tie %req, 'Tie::IxHash',
          $self->revmap_fields(
            content                 => $content,
            litleTxnId              => 'order_number',
            processingInstructions  =>  \%processing,
          );
    }
    elsif ( $action eq 'authReversal' ) {
        push @required_fields, qw( order_number amount );
        tie %req, 'Tie::IxHash',
          $self->revmap_fields(
            content    => $content,
            litleTxnId => 'order_number',
            amount     => 'amount',
          );
    }
    elsif ( $action eq 'accountUpdate' ) {
        push @required_fields, qw( card_number expiration );
        tie %req, 'Tie::IxHash',
          $self->revmap_fields(
            content => $content,
            orderId => 'customer_id',
            card    => \%card,
          );
    }

    $self->required_fields(@required_fields);
    return \%req;
}

sub submit {
    my ($self) = @_;

    $self->is_success(0);

    my %content = $self->content();

    local $SCRUBBER=1;
    $self->_litle_scrubber_init;

    warn 'Pre processing: '.Dumper(\%content) if $DEBUG;
    my $req     = $self->map_request( \%content );
    warn 'Post processing: '.Dumper(\%content) if $DEBUG;
    my $post_data;

    my $writer = new XML::Writer(
        OUTPUT      => \$post_data,
        DATA_MODE   => 1,
        DATA_INDENT => 2,
        ENCODING    => 'utf8',
    );

    ## set the authentication data
    tie my %authentication, 'Tie::IxHash',
      $self->revmap_fields(
        content  => \%content,
        user     => 'login',
        password => 'password',
      );

    warn Dumper($req) if $DEBUG;
    ## Start the XML Document, parent tag
    $writer->xmlDecl();
    $writer->startTag(
        "litleOnlineRequest",
        version    => $self->api_version,
        xmlns      => $self->xmlns,
        merchantId => $content{'merchantid'},
    );

    $self->_xmlwrite( $writer, 'authentication', \%authentication );

    ## partial capture modifier, odd location, because it modifies the start tag :(
    my %extra;
    if ($content{'TransactionType'} eq 'capture'){
        $extra{'partial'} = $content{'partial'} ? 'true' : 'false';
    }

    $writer->startTag(
        $content{'TransactionType'},
        id          => $content{'invoice_number'},
        reportGroup => $content{'report_group'} || 'BOP',
        customerId  => $content{'customer_id'} || 1,
        %extra,
    );
    foreach ( keys( %{$req} ) ) {
        $self->_xmlwrite( $writer, $_, $req->{$_} );
    }

    $writer->endTag( $content{'TransactionType'} );
    $writer->endTag("litleOnlineRequest");
    $writer->end();
    ## END XML Generation

    $self->server_request( scrubber $post_data );
    warn $self->server_request if $DEBUG;

    my ( $page, $status_code, %headers ) = $self->https_post( { 'Content-Type' => 'text/xml;charset:utf-8' } , $post_data);

    $self->server_response( scrubber $page );
    warn Dumper $self->server_response, $status_code, \%headers if $DEBUG;

    my $response = $self->parse_xml_response( $page, $status_code );
    if ( exists( $response->{'response'} ) && $response->{'response'} == 1 ) {
        ## parse error type error
        warn Dumper $response, $self->server_request;
        $self->error_message( $response->{'message'} );
        return;
    } else {
        $self->error_message(
            $response->{ $content{'TransactionType'} . 'Response' }
              ->{'message'} );
    }
    $self->{_response} = $response;

    warn Dumper($response) if $DEBUG;

    ## Set up the data:
    my $resp = $response->{ $content{'TransactionType'} . 'Response' };
    $self->{_response} = $resp;
    $self->order_number( $resp->{'litleTxnId'} || '' );
    $self->result_code( $resp->{'response'}    || '' );
    $resp->{'authCode'} =~ s/\D//g if $resp->{'authCode'};
    $self->authorization( $resp->{'authCode'} || '' );
    $self->cvv2_response( $resp->{'fraudResult'}->{'cardValidationResult'}
          || '' );
    $self->avs_code( $resp->{'fraudResult'}->{'avsResult'} || '' );
    if( $resp->{enhancedAuthResponse}
        && $resp->{enhancedAuthResponse}->{fundingSource}
        && $resp->{enhancedAuthResponse}->{fundingSource}->{type} eq 'PREPAID' ) {

      $self->is_prepaid(1);
      $self->prepaid_balance( $resp->{enhancedAuthResponse}->{fundingSource}->{availableBalance} );
    } else {
      $self->is_prepaid(0);
    }

    #$self->is_dupe( $resp->{'duplicate'} ? 1 : 0 );

    if( $resp->{enhancedAuthResponse}
        && $resp->{enhancedAuthResponse}->{affluence}
      ){
      $self->get_affluence( $resp->{enhancedAuthResponse}->{affluence} );
    }
    $self->is_success( $self->result_code() eq '000' ? 1 : 0 );
    if( $self->result_code() eq '010' ) {
      # Partial approval, if they chose that option
      $self->is_success(1);
    }

    ##Failure Status for 3.0 users
    if ( !$self->is_success ) {
        my $f_status =
            $ERRORS{ $self->result_code }->{'failure'}
          ? $ERRORS{ $self->result_code }->{'failure'}
          : 'decline';
        $self->failure_status($f_status);
    }

    unless ( $self->is_success() ) {
        unless ( $self->error_message() ) {
            $self->error_message( "(HTTPS response: $status_code) "
                  . "(HTTPS headers: "
                  . join( ", ", map { "$_ => " . $headers{$_} } keys %headers )
                  . ") "
                  . "(Raw HTTPS content: ".$self->server_response().")" );
        }
    }

}

=head2 chargeback_retrieve_support_doc

Retrieve a currently uploaded file

 $tx->content(
  login       => 'testdrive',
  password    => '123qwe',
  mercahntid  => '123456',
  case_id     => '001',
  filename    => 'mydoc.pdf',
 );
 $tx->chargeback_retrieve_support_doc();
 $myFileData = $tx->{'fileContent'};

=cut

sub chargeback_retrieve_support_doc {
    my ( $self ) = @_;
    $self->litle_support_doc('RETRIEVE');
    if ($self->is_success) { $self->{'fileContent'} = $self->{'_response'}; } else { $self->{'fileContent'} = undef; }
}

=head2 chargeback_delete_support_doc

Delete a currently uploaded file.  Follows the same format as chargeback_retrieve_support_doc

=cut

sub chargeback_delete_support_doc {
    my ( $self ) = @_;
    $self->litle_support_doc('DELETE' );
}

=head2 chargeback_upload_support_doc

Upload a new file

 $tx->content(
  login       => 'testdrive',
  password    => '123qwe',
  mercahntid  => '123456',
  case_id     => '001',
  filename    => 'mydoc.pdf',
  filecontent => $binaryPdfData,
  mimetype    => 'applicatoin/pdf',
 );
 $tx->chargeback_upload_support_doc();

=cut

sub chargeback_upload_support_doc {
    my ( $self ) = @_;
    $self->litle_support_doc('UPLOAD' );
}

=head2 chargeback_replace_support_doc

Replace a previously uploaded file.  Follows the same format as chargeback_upload_support_doc

=cut

sub chargeback_replace_support_doc {
    my ( $self ) = @_;
    $self->litle_support_doc('REPLACE' );
}

sub litle_support_doc {
    my ( $self, $action ) = @_;

    $self->is_success(0);
    my %content = $self->content();

    local $SCRUBBER=1;
    $self->_litle_scrubber_init;

    my $requiredargs = ['case_id','filename','merchantid'];
    if ($action =~ /(?:UPLOAD|REPLACE)/) { push @$requiredargs, 'filecontent', 'mimetype'; }
    foreach my $key (@$requiredargs) {
        croak "Missing arg $key" unless $content{$key};
    }

    my $actionRESTful = {
        'DELETE' => 'DELETE',
        'RETRIEVE' => 'GET',
        'UPLOAD' => 'POST',
        'REPLACE' => 'PUT',
    };
    die "UNDEFINED ACTION: $action" unless defined $actionRESTful->{$action};

    {
      use bytes;
      if ( defined $content{'filecontent'} ) {
          if ( length($content{'filecontent'}) > 2097152 ) { # file limit of 2M
              my $msg = 'Filesize Exceeds Limit Of 2MB';
              $self->result_code( 012 );
              $self->error_message( $msg );
              croak $msg;
          }
          my $allowedTypes = {
              'application/pdf' => 1,
              'image/gif' => 1,
              'image/jpeg' => 1,
              'image/png' => 1,
              'image/tiff' => 1,
          };
          if ( ! defined $allowedTypes->{$content{'mimetype'}||''} ) {
              croak "File must be one of PDF/GIF/JPG/PNG/TIFF".$content{'mimetype'};
          }
      }
    }

    my $caseidURI = $content{'case_id'};
    my $filenameURI = $content{'filename'};
    my $merchantidURI = $content{'merchantid'};
    foreach ( $caseidURI, $filenameURI, $merchantidURI ) {
        s/([^a-z0-9\.\-])/sprintf('%%%X',ord($1))/ige;
    }

    my $url = 'https://'.$self->chargeback_server.':'.$self->chargeback_port.'//services/chargebacks/documents/'.$merchantidURI.'/'.$caseidURI.'/'.$filenameURI;
    my $response = HTTP::Tiny->new( verify_SSL=>$self->verify_SSL )->request($actionRESTful->{$action}, $url, {
        headers => {
            'Authorization' => 'Basic ' . MIME::Base64::encode("$content{'login'}:$content{'password'}",''),
            'Content-Type' => $content{'mimetype'} || 'text/plain',
        },
        content => $content{'filecontent'},
    } );

    $self->server_request( scrubber $content{'mimetype'} );
    $self->server_response( scrubber $response->{'content'} );

    if ( $action eq 'RETRIEVE' && $response->{'status'} =~ /^200/ && substr($response->{'content'},0,500) !~ /<Merchant/x) {
        # the RETRIEVE action returns the actual page as the file, rather then returning XML
        $self->is_success(1);
    } else {
        my $xml_response = $self->parse_xml_response( $response->{'content'}, $response->{'status'} );

        if (defined $xml_response && defined $xml_response->{'ChargebackCase'}{'Document'}{'ResponseCode'}) {
            $self->is_success( $xml_response->{'ChargebackCase'}{'Document'}{'ResponseCode'} eq '000' ? 1 : 0 );
            $self->result_code( $xml_response->{'ChargebackCase'}{'Document'}{'ResponseCode'} );
            $self->error_message( $xml_response->{'ChargebackCase'}{'Document'}{'ResponseMessage'} );
        } else {
            croak "UNRECOGNIZED RESULT: ".$self->server_response;
        }
    }
}

=head2 list_support_docs

Return a hashref that contains a list of files that already exist on the server.

 $tx->content(
  login       => 'testdrive',
  password    => '123qwe',
  mercahntid  => '123456',
  case_id     => '001',
 );
 my $ret = $tx->chargeback_list_support_docs();

Currently this returns in this format

 $ret = {
   'file1' => {},
   'file2' => {},
 };

Litle does not currently send any file attributes.  However the hash is built for future expansion.

=cut

sub chargeback_list_support_docs {
    my ( $self ) = @_;

    $self->is_success(0);

    my %content = $self->content();
    local $SCRUBBER=1;
    $self->_litle_scrubber_init;

    croak "Missing arg case_id" unless $content{'case_id'};
    croak "Missing arg merchantid" unless $content{'merchantid'};
    my $caseidURI = $content{'case_id'};
    my $merchantidURI = $content{'merchantid'};
    foreach ( $caseidURI, $merchantidURI ) {
        s/([^a-z0-9\.\-])/sprintf('%%%X',ord($1))/ige;
    }

    my $url = 'https://'.$self->chargeback_server.':'.$self->chargeback_port.'//services/chargebacks/documents/'.$merchantidURI.'/'.$caseidURI.'/';
    my $response = HTTP::Tiny->new( verify_SSL=>$self->verify_SSL )->request('GET', $url, {
        headers => { Authorization => 'Basic ' . MIME::Base64::encode("$content{'login'}:$content{'password'}",'') },
    } );

    $self->server_request( scrubber $url );
    $self->server_response( scrubber $response->{'content'} );

    my $xml_response = $self->parse_xml_response( $response->{'content'}, $response->{'status'} );

    if (defined $xml_response && $xml_response->{'ChargebackCase'}{'ResponseCode'}) {
        $self->result_code( $xml_response->{'ChargebackCase'}{'ResponseCode'} );
        $self->error_message( $xml_response->{'ChargebackCase'}{'ResponseMessage'} );
    } elsif (defined $xml_response && $xml_response->{'ChargebackCase'}{'DocumentEntry'}) {
        $self->is_success(1);
        $self->result_code( '000' );

    my $ref = $xml_response->{'ChargebackCase'}{'DocumentEntry'};
    if (defined $ref->{'id'} && ref $ref->{'id'} eq '') {
        # XMLin does not parse the result properly for a single document.  This fixes the single document format to match the multi-doc format
        $ref = { $ref->{'id'} => $ref };
        }
    return $ref;
    } else {
        croak "UNRECOGNIZED RESULT: ".$self->server_response;
    }
    return {};
}

sub parse_xml_response {
    my ( $self, $page, $status_code ) = @_;
    my $response = {};
    if ( $status_code =~ /^200/ ) {
        if ( ! eval { $response = XMLin($page); } ) {
            die "XML PARSING FAILURE: $@";
        }
    }
    else {
        $status_code =~ s/[\r\n\s]+$//; # remove newline so you can see the error in a linux console
        if ( $status_code =~ /^(?:900|599)/ ) { $status_code .= ' - verify Litle has whitelisted your IP'; }
        die "CONNECTION FAILURE: $status_code";
    }
    return $response;
}

sub parse_batch_response {
    my ( $self, $args ) = @_;
    my @results;
    my $resp = $self->{'batch_response'};
    $self->order_number( $resp->{'litleBatchId'} );

    #$self->invoice_number( $resp->{'id'} );
    my @result_types =
      grep { $_ =~ m/Response$/ }
      keys %{$resp};    ## get a list of result types in this batch
    return {
        'account_update' => $self->get_update_response,
        ## do the other response types now
    };
}

=head2 add_item

A new method, not supported under BOP yet, but interface to adding multiple entries, so we can write and interface with batches

 $tx->add_item( \%content );

=cut

sub add_item {
    my $self = shift;
    ## do we want to render it now, or later?
    push @{ $self->{'batch_entries'} }, shift;
}

sub create_batch {
    my ( $self, %opts ) = @_;

    $self->is_success(0);

    local $SCRUBBER=1;
    $self->_litle_scrubber_init;

    if ( scalar( @{ $self->{'batch_entries'} } ) < 1 ) {
        $self->error('Cannot create an empty batch');
        return;
    }

    my $post_data;

    my $writer = new XML::Writer(
        OUTPUT      => \$post_data,
        DATA_MODE   => 1,
        DATA_INDENT => 2,
        ENCODING    => 'utf8',
    );
    ## set the authentication data
    tie my %authentication, 'Tie::IxHash',
      $self->revmap_fields(
        content  => \%opts,
        user     => 'login',
        password => 'password',
      );

    ## Start the XML Document, parent tag
    $writer->xmlDecl();
    $writer->startTag(
        "litleRequest",
        version => $self->batch_api_version,
        xmlns   => $self->xmlns,
        id      => $opts{'batch_id'} || time,
        numBatchRequests => 1,  #hardcoded for now, not doing multiple merchants
    );

    ## authentication
    $self->_xmlwrite( $writer, 'authentication', \%authentication );
    ## batch Request tag
    $writer->startTag(
        'batchRequest',
        id => $opts{'batch_id'} || time,
        numAccountUpdates => scalar( @{ $self->{'batch_entries'} } ),
        merchantId        => $opts{'merchantid'},
    );
    foreach my $entry ( @{ $self->{'batch_entries'} } ) {
        $self->content( %{$entry} );
        my %content = $self->content;
        my $req     = $self->map_request( \%content );
        $writer->startTag(
            $content{'TransactionType'},
            id          => $content{'invoice_number'},
            reportGroup => $content{'report_group'} || 'BOP',
            customerId  => $content{'customer_id'} || 1,
        );
        foreach ( keys( %{$req} ) ) {
            $self->_xmlwrite( $writer, $_, $req->{$_} );
        }
        $writer->endTag( $content{'TransactionType'} );
        ## need to also handle the action tag here, and custid info
    }
    $writer->endTag("batchRequest");
    $writer->endTag("litleRequest");
    $writer->end();
    ## END XML Generation

    #----- Send it
    if ( $opts{'method'} && $opts{'method'} eq 'sftp' ) {    #FTP
        require Net::SFTP::Foreign;
        my $sftp = Net::SFTP::Foreign->new(
            $self->server(),
            user     => $opts{'ftp_username'},
            password => $opts{'ftp_password'},
        );
        $sftp->error and die "SSH connection failed: " . $sftp->error;

        $sftp->setcwd("inbound")
          or die "Cannot change working directory ", $sftp->error;
        ## save the file out, can't put directly from var, and is multibyte, so issues from filehandle

        my $filename = $opts{'batch_id'} || $opts{'login'} . "_" . time;
        $sftp->put_content( $post_data, "$filename.prg" )
          or die "Cannot PUT $filename", $sftp->error;
        $sftp->rename( "$filename.prg",
            "$filename.asc" ) #once complete, you rename it, for pickup
          or die "Cannot RENAME file", $sftp->message;
        $self->is_success(1);
    }
    elsif ( $opts{'method'} && $opts{'method'} eq 'https' ) {    #https post
        $self->port('15000');
        $self->path('/');
        my ( $page, $status_code, %headers ) =
          $self->https_post($post_data);
        $self->server_request( scrubber $post_data );
        $self->server_response( scrubber $page );
        warn $self->server_request if $DEBUG;

        warn Dumper [ $page, $status_code, \%headers ] if $DEBUG;

        my $response = {};
        if ( $status_code =~ /^200/ ) {
            if ( ! eval { $response = XMLin($page); } ) {
                die "XML PARSING FAILURE: $@";
            }
            elsif ( exists( $response->{'response'} )
                && $response->{'response'} == 1 )
            {
                ## parse error type error
                warn Dumper( $response, $self->server_request );
                $self->error_message( $response->{'message'} );
                return;
            }
            else {
                $self->error_message(
                    $response->{'batchResponse'}->{'message'} );
            }
        }
        else {
            die "CONNECTION FAILURE: $status_code";
        }
        $self->{_response} = $response;

        ##parse out the batch info as our general status
        my $resp = $response->{'batchResponse'};
        $self->order_number( $resp->{'litleSessionId'} );
        $self->result_code( $response->{'response'} );
        $self->is_success( $response->{'response'} eq '0' ? 1 : 0 );

        warn Dumper($response) if $DEBUG;
        unless ( $self->is_success() ) {
            unless ( $self->error_message() ) {
                $self->error_message(
                        "(HTTPS response: $status_code) "
                      . "(HTTPS headers: "
                      . join( ", ",
                        map { "$_ => " . $headers{$_} } keys %headers )
                      . ") "
                      . "(Raw HTTPS content: $page)"
                );
            }
        }
        if ( $self->is_success() ) {
            $self->{'batch_response'} = $resp;
        }
    }

}

sub send_rfr {
    my ( $self, $args ) = @_;
    my $post_data;

    local $SCRUBBER=1;
    $self->_litle_scrubber_init;

    $self->is_success(0);
    my $writer = new XML::Writer(
        OUTPUT      => \$post_data,
        DATA_MODE   => 1,
        DATA_INDENT => 2,
        ENCODING    => 'utf8',
    );
    ## set the authentication data
    tie my %authentication, 'Tie::IxHash',
      $self->revmap_fields(
        content  => $args,
        user     => 'login',
        password => 'password',
      );

    ## Start the XML Document, parent tag
    $writer->xmlDecl();
    $writer->startTag(
        "litleRequest",
        version          => $self->batch_api_version,
        xmlns            => $self->xmlns,
        numBatchRequests => 0,
    );

    ## authentication
    $self->_xmlwrite( $writer, 'authentication', \%authentication );
    ## batch Request tag
    $writer->startTag('RFRRequest');
    $writer->startTag('accountUpdateFileRequestData');
    $writer->startTag('merchantId');
    $writer->characters( $args->{'merchantid'} );
    $writer->endTag('merchantId');
    $writer->startTag('postDay');
    $writer->characters( $args->{'date'} );
    $writer->endTag('postDay');
    $writer->endTag('accountUpdateFileRequestData');
    $writer->endTag("RFRRequest");
    $writer->endTag("litleRequest");
    $writer->end();
    ## END XML Generation
    #
    $self->port('15000');
    $self->path('/');
    my ( $page, $status_code, %headers ) = $self->https_post($post_data);

    $self->server_request( scrubber $post_data );
    $self->server_response( scrubber $page );
    warn $self->server_request if $DEBUG;

    warn Dumper [ $page, $status_code, \%headers ] if $DEBUG;

    my $response = {};
    if ( $status_code =~ /^200/ ) {
        if ( ! eval { $response = XMLin($page); } ) {
            die "XML PARSING FAILURE: $@";
        }
        elsif ( exists( $response->{'response'} ) && $response->{'response'} == 1 )
        {
            ## parse error type error
            warn Dumper( $response, $self->server_request );
            $self->error_message( $response->{'message'} );
            return;
        }
        else {
            $self->error_message( $response->{'RFRResponse'}->{'message'} );
        }
    }
    else {
        die "CONNECTION FAILURE: $status_code";
    }
    $self->{_response} = $response;
    if ( $response->{'RFRResponse'} ) {
        ## litle returns an 'error' if the file is not done. So it's not ready yet.
        $self->result_code( $response->{'RFRResponse'}->{'response'} );
        return;
    }
    else {

      #if processed, it returns as a batch, so, success, and let get the details
        my $resp = $response->{'batchResponse'};
        $self->is_success( $resp->{'response'} eq '000' ? 1 : 0 );
        $self->{'batch_response'} = $resp;
        $self->parse_batch_response;
    }
}

sub retrieve_batch {
    my ( $self, %opts ) = @_;

    local $SCRUBBER=1;
    $self->_litle_scrubber_init;

    croak "Missing filename" if !$opts{'batch_id'};
    my $post_data;
    if ( $opts{'batch_return'} ) {
        ## passed in data structure
        $post_data = $opts{'batch_return'};
    }
    else {
        ## go download a batch
        require Net::SFTP::Foreign;
        my $sftp = Net::SFTP::Foreign->new(
            $self->server(),
            user     => $opts{'ftp_username'},
            password => $opts{'ftp_password'},
        );
        $sftp->error and die "SSH connection failed: " . $sftp->error;

        $sftp->setcwd("outbound")
          or die "Cannot change working directory ", $sftp->error;

        my $filename = $opts{'batch_id'};
        $post_data = $sftp->get_content( $filename )
          or die "Cannot GET $filename", $sftp->error;
        $self->is_success(1);
        warn $post_data if $DEBUG;
    }

    my $response = {};
    if ( ! eval { $response = XMLin($post_data); } ) {
        die "XML PARSING FAILURE: $@";
    }
    elsif ( exists( $response->{'response'} ) && $response->{'response'} == 1 ) {
        ## parse error type error
        warn Dumper( $response, $self->{'_post_data'} );
        $self->error_message( $response->{'message'} );
        return;
    }
    else {
        $self->error_message( $response->{'batchResponse'}->{'message'} );
    }

    $self->server_request( scrubber $post_data );
    $self->server_response( scrubber $response );

    $self->{_response} = $response;
    my $resp = $response->{'batchResponse'};
    $self->order_number( $resp->{'litleSessionId'} );
    $self->result_code( $response->{'response'} );
    $self->is_success( $response->{'response'} eq '0' ? 1 : 0 );
    if ( $self->is_success() ) {
        $self->{'batch_response'} = $resp;
        return $self->parse_batch_response;
    }
}

sub get_update_response {
    my $self = shift;
    require Business::OnlinePayment::Litle::UpdaterResponse;
    my @response;
    foreach
      my $item ( @{ $self->{'batch_response'}->{'accountUpdateResponse'} } )
    {
        push @response,
          Business::OnlinePayment::Litle::UpdaterResponse->new( $item );
    }
    return \@response;
}

sub revmap_fields {
    my $self = shift;
    tie my (%map), 'Tie::IxHash', @_;
    my %content;
    if ( $map{'content'} && ref( $map{'content'} ) eq 'HASH' ) {
        %content = %{ delete( $map{'content'} ) };
    }
    else {
        warn "WARNING: This content has no been pre-processed with map_fields";
        %content = $self->content();
    }

    map {
        my $value;
        if ( ref( $map{$_} ) eq 'HASH' ) {
            $value = $map{$_} if ( keys %{ $map{$_} } );
        }
        elsif ( ref( $map{$_} ) eq 'ARRAY' ) {
            $value = $map{$_};
        }
        elsif ( ref( $map{$_} ) ) {
            $value = ${ $map{$_} };
        }
        elsif ( exists( $content{ $map{$_} } ) ) {
            $value = $content{ $map{$_} };
        }

        if ( defined($value) ) {
            ( $_ => $value );
        }
        else {
            ();
        }
    } ( keys %map );
}

sub _xmlwrite {
    my ( $self, $writer, $item, $value ) = @_;
    if ( ref($value) eq 'HASH' ) {
        my $attr = $value->{'attr'} ? $value->{'attr'} : {};
        $writer->startTag( $item, %{$attr} );
        foreach ( keys(%$value) ) {
            next if $_ eq 'attr';
            $self->_xmlwrite( $writer, $_, $value->{$_} );
        }
        $writer->endTag($item);
    }
    elsif ( ref($value) eq 'ARRAY' ) {
        foreach ( @{$value} ) {
            $self->_xmlwrite( $writer, $item, $_ );
        }
    }
    else {
        $writer->startTag($item);
        utf8::decode($value); # prevent double byte corruption in the xml output
        $writer->characters($value);
        $writer->endTag($item);
    }
}

sub _litle_scrubber_init {
    my ( $self ) = @_;
    my %content = $self->content();
    scrubber_init({
        quotemeta($content{'password'}||'')=>'DELETED',
        quotemeta($content{'ftp_password'}||'')=>'DELETED',
        quotemeta($content{'card_number'}||'')=>'DELETED',
        ($content{'cvv2'} ? '(?<=[^\d])'.quotemeta($content{'cvv2'}).'(?=[^\d])' : '')=>'DELETED',
        });
}

#------------------------------------ Chargebacks

sub chargeback_activity_request {
    my ( $self ) = @_;
    my $post_data;

    $self->is_success(0);
    my %content = $self->content();

    local $SCRUBBER=1;
    $self->_litle_scrubber_init;

    ## activity_date
    ## Type = Date; Format = YYYY-MM-DD
    if ( ! $content{'activity_date'} || $content{'activity_date'} !~ m/^\d{4}-(\d{2})-(\d{2})$/ || $1 > 12 || $2 > 31) {
        die "Invalid Date Pattern, YYYY-MM-DD required:"
          . ( $content{'activity_date'} || 'undef');
    }
    #
    ## financials only [true,false]
    # The financialOnly element is an optional child of the litleChargebackActivitiesRequest element.
    # You use this flag in combination with the activityDate element to specify a request for chargeback financial activities that occurred on the specified date.
    # A value of true returns only activities that had financial impact on the specified date.
    # A value of false returns all activities on the specified date.
    #Type = Boolean; Valid Values = true or false
    my $financials;
    if ( defined( $content{'financial_only'} ) ) {
        $financials = $content{'financial_only'} ? 'true' : 'false';
    }
    else {
        $financials = 'false';
    }

    my $writer = new XML::Writer(
        OUTPUT      => \$post_data,
        DATA_MODE   => 1,
        DATA_INDENT => 2,
        ENCODING    => 'utf8',
    );
    ## set the authentication data
    tie my %authentication, 'Tie::IxHash',
      $self->revmap_fields(
        content  => \%content,
        user     => 'login',
        password => 'password',
      );

    ## Start the XML Document, parent tag
    $writer->xmlDecl();
    $writer->startTag(
        "litleChargebackActivitiesRequest",
        version => $self->chargeback_api_version,
        xmlns   => $self->xmlns,
    );

    ## authentication
    $self->_xmlwrite( $writer, 'authentication', \%authentication );
    ## batch Request tag
    $writer->startTag('activityDate');
      $writer->characters( $content{'activity_date'} );
    $writer->endTag('activityDate');
    $writer->startTag('financialOnly');
      $writer->characters($financials);
    $writer->endTag('financialOnly');
    $writer->endTag("litleChargebackActivitiesRequest");
    $writer->end();
    ## END XML Generation

    $self->{'_post_data'} = $post_data;
    warn $self->{'_post_data'} if $DEBUG;
    #my ( $page, $status_code, %headers ) = $self->https_post( { 'Content-Type' => 'text/xml;charset:utf-8' } , $post_data);
    my $url = 'https://'.$self->chargeback_server.':'.$self->chargeback_port.'/'.$self->chargeback_path;
    my $tiny_response = HTTP::Tiny->new( verify_SSL=>$self->verify_SSL )->request('POST', $url, {
        headers => { 'Content-Type' => 'text/xml;charset:utf-8', },
        content => $post_data,
    } );

    my $page = $tiny_response->{'content'};
    $self->server_response( $page );
    my $status_code = $tiny_response->{'status'};
    my %headers = %{$tiny_response->{'headers'}};

    warn Dumper $page, $status_code, \%headers if $DEBUG;

    my $response = {};
    if ( $status_code =~ /^200/ ) {
        ## Failed to parse
        if ( !eval { $response = XMLin($page); } ) {
            die "XML PARSING FAILURE: $@, $page";
        }    ## well-formed failure message
        elsif ( exists( $response->{'response'} )
            && $response->{'response'} == 1 )
        {
            ## parse error type error
            warn Dumper( $response, $self->{'_post_data'} );
            $self->error_message( $response->{'message'} );
            return;
        }    ## success message
        else {
            $self->error_message(
                $response->{'litleChargebackActivitiesResponse'}->{'message'} );
            $self->is_success(1);
        }
    }
    else {
        $status_code =~ s/[\r\n\s]+$//
          ;    # remove newline so you can see the error in a linux console
        if ( $status_code =~ /^(?:900|599)/ ) {
            $status_code .= ' - verify Litle has whitelisted your IP';
        }
        die "CONNECTION FAILURE: $status_code";
    }
    $self->{_response} = $response;

    my @response_list;
    if (defined $response->{caseActivity} && ref $response->{caseActivity} ne 'ARRAY') {
        $response->{caseActivity} = [$response->{caseActivity}]; # make sure we are an array
    }
    require Business::OnlinePayment::Litle::ChargebackActivityResponse;
    foreach my $case ( @{ $response->{caseActivity} } ) {
       push @response_list,
       Business::OnlinePayment::Litle::ChargebackActivityResponse->new($case);
    }

    warn Dumper($response) if $DEBUG;
    return \@response_list;
}

sub chargeback_update_request {
    my ( $self ) = @_;
    my $post_data;

    $self->is_success(0);
    my %content = $self->content();

    local $SCRUBBER=1;
    $self->_litle_scrubber_init;

    foreach my $key (qw(case_id merchant_activity_id activity )) {
        ## case_id
        ## merchant_activity_id
        ## activity
      croak "Missing arg $key" unless $content{$key};
    }

    my $writer = new XML::Writer(
        OUTPUT      => \$post_data,
        DATA_MODE   => 1,
        DATA_INDENT => 2,
        ENCODING    => 'utf-8',
    );
    ## set the authentication data
    tie my %authentication, 'Tie::IxHash',
      $self->revmap_fields(
        content  => \%content,
        user     => 'login',
        password => 'password',
      );

    ## Start the XML Document, parent tag
    $writer->xmlDecl();
    $writer->startTag(
        "litleChargebackUpdateRequest",
        version => $self->chargeback_api_version,
        xmlns   => $self->xmlns,
    );

    ## authentication
      $self->_xmlwrite( $writer, 'authentication', \%authentication );
      $writer->startTag('caseUpdate');
        $writer->startTag('caseId');
          $writer->characters( $content{'case_id'} );
        $writer->endTag('caseId');

        $writer->startTag('merchantActivityId');
          $writer->characters( $content{'merchant_activity_id'} );
        $writer->endTag('merchantActivityId');

        $writer->startTag('activity');
          $writer->characters( $content{'activity'} );
        $writer->endTag('activity');

      $writer->endTag('caseUpdate');
    $writer->endTag("litleChargebackUpdateRequest");
    $writer->end();
    ## END XML Generation

    $self->{'_post_data'} = $post_data;
    warn $self->{'_post_data'} if $DEBUG;
    #my ( $page, $status_code, %headers ) = $self->https_post($post_data);
    my $url = 'https://'.$self->chargeback_server.':'.$self->chargeback_port.'/'.$self->chargeback_path;
    my $tiny_response = HTTP::Tiny->new( verify_SSL=>$self->verify_SSL )->request('POST', $url, {
        headers => { 'Content-Type' => 'text/xml;charset:utf-8', },
        content => $post_data,
    } );

    my $page = $tiny_response->{'content'};
    $self->server_response( $page );
    my $status_code = $tiny_response->{'status'};
    my %headers = %{$tiny_response->{'headers'}};

    warn Dumper $page, $status_code, \%headers if $DEBUG;

    my $response = {};
    if ( $status_code =~ /^200/ ) {
        ## Failed to parse
        if ( !eval { $response = XMLin($page); } ) {
            die "XML PARSING FAILURE: $@, $page";
        }    ## well-formed failure message
        $self->{_response} = $response;
        if ( exists( $response->{'response'} ) ) {
            ## parse error type error
            warn Dumper( $response, $self->{'_post_data'} );
            $self->result_code( $response->{'response'} ); # 0 - success, 1 invalid xml
            $self->error_message( $response->{'message'} );
            $self->phoenixTxnId( $response->{'caseUpdateResponse'}{'phoenixTxnId'} );
            $self->is_success(1);
            return $response->{'caseUpdateResponse'}{'phoenixTxnId'};
        }
        else {
        die "UNKNOWN XML RESULT: $page";
        }
    }
    else {
        $status_code =~ s/[\r\n\s]+$//
          ;    # remove newline so you can see the error in a linux console
        if ( $status_code =~ /^(?:900|599)/ ) {
            $status_code .= ' - verify Litle has whitelisted your IP';
        }
        die "CONNECTION FAILURE: $status_code";
    }
}

=head1 AUTHORS

Jason Hall, C<< <jayce at lug-nut.com> >>

Jason Terry

=head1 UNIMPLEMENTED

Certain features are not yet implemented (no current personal business need), though the capability of support is there, and the test data for the verification suite is there.

    Force Capture
    Capture Given Auth
    3DS
    billMeLater

=head1 BUGS

Please report any bugs or feature requests to C<bug-business-onlinepayment-litle at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Business-OnlinePayment-Litle>. I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

You may also add to the code via github, at L<http://github.com/Jayceh/Business--OnlinePayment--Litle.git>


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

Heavily based on Jeff Finucane's l<Business::OnlinePayment::IPPay> because it also required dynamically writing XML formatted docs to a gateway.

=head1 COPYRIGHT & LICENSE

Copyright 2012 Jason Hall.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=back


=head1 SEE ALSO

perl(1). L<Business::OnlinePayment>


=cut

1; # End of Business::OnlinePayment::Litle
