#!/usr/bin/perl -w

use Test::More qw(no_plan);

## grab info from the ENV
my $login = $ENV{'BOP_USERNAME'} ? $ENV{'BOP_USERNAME'} : 'TESTMERCHANT';
my $password = $ENV{'BOP_PASSWORD'} ? $ENV{'BOP_PASSWORD'} : 'TESTPASS';
my $merchantid = $ENV{'BOP_MERCHANTID'} ? $ENV{'BOP_MERCHANTID'} : 'TESTMERCHANTID';
my @opts = ('default_Origin' => 'RECURRING' );

use_ok 'Business::OnlinePayment';

my %orig_content = (
    type           => 'CC',
    login          => $login,
    password       => $password,
    merchantid     =>  $merchantid,
    action         => 'Authorization Only', #'Normal Authorization',
    description    => 'BLU*BusinessOnlinePayment',
    affiliate      => '123',
    recycle_by     => 'Merchant',
    recycle_id     => '1',
#    card_number    => '4007000000027',
    card_number    => '4457010000000009',
    cvv2           => '123',
    expiration     => expiration_date(),
    amount         => '49.95',
    name           => 'Tofu Beast',
    email          => 'ippay@weasellips.com',
    address        => '123 Anystreet',
    city           => 'Anywhere',
    state          => 'UT',
    zip            => '84058',
    country        => 'US',      # will be forced to USA
    customer_id    => 'tfb',
    company_phone  => '801.123-4567',
    url            =>  'support.foo.com',
    invoice_number => '1234',
    ip             =>  '127.0.0.1',
    ship_name      =>  'Tofu Beast, Co.',
    ship_address   =>  '123 Anystreet',
    ship_city      => 'Anywhere',
    ship_state     => 'UT',
    ship_zip       => '84058',
    ship_country   => 'US',      # will be forced to USA
    tax            => 0,
    products        =>  [
    {   description =>  'First Product',
        quantity    =>  1,
        units       =>  'Months',
        amount      =>  500,
        discount    =>  0,
        code        =>  1,
        cost        =>  500,
        tax         =>  0,
        totalwithtax => 500,
    },
    {   description =>  'Second Product',
        quantity    =>  1,
        units       =>  'Months',
        amount      =>  1500,
        discount    =>  0,
        code        =>  2,
        cost        =>  500,
        tax         =>  0,
        totalwithtax => 1500,
    }

    ],
);

my $tx = Business::OnlinePayment->new("Litle", @opts);
my %content = %orig_content;
$tx->content(%content);
tx_check(
	$tx,
	desc          => "Auth Only",
	is_success    => '1',
	result_code   => '000',
	error_message => 'Approved',
	approved_amount => undef,
);

$orig_content{'action'} = 'Normal Authorization';
%content = %orig_content;
$tx->content(%content);
tx_check(
	$tx,
	desc          => "Normal Auth",
	is_success    => '1',
	result_code   => '000',
	error_message => 'Approved',
	approved_amount => undef,
);

$orig_content{'action'} = 'Normal Authorization';
%content = %orig_content;
$content{'card_number'} = '';
$content{'card_token'} = '0000000000000';
$tx->content(%content);
tx_check(
	$tx,
	desc          => "Normal Auth",
	is_success    => '1',
	result_code   => '000',
	error_message => 'Approved',
	approved_amount => undef,
);

sub tx_check {
    my $tx = shift;
    my %o  = @_;

    $tx->test_transaction('sandbox');
    $tx->submit;

    is( $tx->is_success,    $o{is_success},    "$o{desc}: " . tx_info($tx) );
    is( $tx->result_code,   $o{result_code},   "result_code(): RESULT" );
    is( $tx->error_message, $o{error_message}, "error_message() / RESPMSG" );
    if( $o{authorization} ){
        is( $tx->authorization, $o{authorization}, "authorization() / AUTHCODE" );
    }
    if( $o{avs_code} ){
        is( $tx->avs_code,  $o{avs_code},  "avs_code() / AVSADDR and AVSZIP" );
    }
    if( $o{cvv2_response} ){
        is( $tx->cvv2_response, $o{cvv2_response}, "cvv2_response() / CVV2MATCH" );
    }
    if( $o{approved_amount} ){
        is( $tx->{_response}->{approvedAmount}, $o{approved_amount}, "approved_amount() / Partial Approval Amount" );
    }
    like( $tx->order_number, qr/^\w{5,19}/, "order_number() / PNREF" );
}

sub tx_info {
    my $tx = shift;

    no warnings 'uninitialized';

    return (
        join( "",
            "is_success(",     $tx->is_success,    ")",
            " order_number(",  $tx->order_number,  ")",
            " error_message(", $tx->error_message, ")",
            " result_code(",   $tx->result_code,   ")",
            " auth_info(",     $tx->authorization, ")",
            " avs_code(",      $tx->avs_code,      ")",
            " cvv2_response(", $tx->cvv2_response, ")",
        )
    );
}

sub expiration_date {
    my($month, $year) = (localtime)[4,5];
    $year++;       # So we expire next year.
    $year %= 100;  # y2k?  What's that?

    return sprintf("%02d%02d", $month, $year);
}
