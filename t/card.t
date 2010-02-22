#!/usr/bin/perl -w

use Test::More;
print $ENV{'BOP_USERNAME'};
my $login = $ENV{'BOP_USERNAME'} ? $ENV{'BOP_USERNAME'} : 'TESTMERCHANT';
my $password = $ENV{'BOP_PASSWORD'} ? $ENV{'BOP_PASSWORD'} : 'TESTPASS';
my $merchantid = $ENV{'BOP_MERCHANTID'} ? $ENV{'BOP_MERCHANTID'} : 'TESTMERCHANTID';
my @opts = ('default_Origin' => 'RECURRING' );
plan tests => 43;
  
use_ok 'Business::OnlinePayment';

my %content = (
    type           => 'VISA',
    login          => $login,
    password       => $password,
    merchantid      =>  $merchantid,
    action         => 'Normal Authorization',
    description    => 'FST*BusinessOnlinePayment',
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
    company_phone   => '801.123-4567',
    url             =>  'support.foo.com',
    invoice_number  => '1234',
    products        =>  [
    {   description =>  'First Product',
        sku         =>  'sku',
        quantity    =>  1,
        units       =>  'Months',
        amount      =>  500,
        discount    =>  0,
        code        =>  1,
        cost        =>  500,
    },
    {   description =>  'Second Product',
        sku         =>  'sku',
        quantity    =>  1,
        units       =>  'Months',
        amount      =>  1500,
        discount    =>  0,
        code        =>  2,
        cost        =>  500,
    }

    ],
);

my $voidable;
my $voidable_auth;
my $voidable_amount = 0;

# valid card number test
{
  my $tx = Business::OnlinePayment->new("Litle", @opts);
  $tx->content(%content);
  tx_check(
    $tx,
    desc          => "valid card_number",
    is_success    => 1,
    result_code   => '000',
    error_message => 'APPROVED',
    authorization => qr/TEST\d{2}/,
    avs_code      => 'U',          # so rather pointless :\
    cvv2_response => 'P',          # ...
  );
  $voidable = $tx->order_number if $tx->is_success;
  $voidable_auth = $tx->authorization if $tx->is_success;
  $voidable_amount = $content{amount} if $tx->is_success;
}

## invalid card number test
#{
#  my $tx = Business::OnlinePayment->new("Litle", @opts);
#  $tx->content(%content, card_number => "4111111111111112" );
#  tx_check(
#    $tx,
#    desc          => "invalid card_number",
#    is_success    => 0,
#    result_code   => '912',
#    error_message => 'INVALID CARD NUMBER',
#    authorization => qr/^$/,
#    avs_code      => '',           # so rather pointless :\
#    cvv2_response => '',           # ...
#  );
#}
#
## authorization only test
#{
#  my $tx = Business::OnlinePayment->new("Litle", @opts);
#  $tx->content(%content, action => 'authorization only',  amount => '3.00' );
#  tx_check(
#    $tx,
#    desc          => "authorization only",
#    is_success    => 1,
#    result_code   => '000',
#    error_message => 'APPROVED',
#    authorization => qr/TEST\d{2}/,
#    avs_code      => 'U',          # so rather pointless :\
#    cvv2_response => 'P',          # ...
#  );
#  $postable = $tx->order_number if $tx->is_success;
#  $postable_auth = $tx->authorization if $tx->is_success;
#  $postable_amount = $content{amount} if $tx->is_success;
#}
#
## post authorization test
#SKIP: {
#  my $tx = new Business::OnlinePayment( "Litle", %opts );
#  $tx->content( %content, 'action'       => "post authorization", 
#                          'amount'       => $postable_amount,    # not required
#                          'order_number' => $postable,
#              );
#  tx_check(
#    $tx,
#    desc          => "post authorization",
#    is_success    => 1,
#    result_code   => '000',
#    error_message => 'APPROVED',
#    authorization => qr/^$postable_auth$/,
#    avs_code      => '',
#    cvv2_response => '',
#    );
#}
#
## void test
#SKIP: {
#  my $tx = new Business::OnlinePayment( "Litle", %opts );
#  $tx->content( %content, 'action' => "Void",
#                          'order_number' => $voidable,
#                          'authorization' => $voidable_auth,
#              );
#  tx_check(
#    $tx,
#    desc          => "void",
#    is_success    => 1,
#    result_code   => '000',
#    error_message => 'VOID PROCESSED',
#    authorization => qr/^$voidable_auth$/,
#    avs_code      => '',
#    cvv2_response => '',
#    );
#}
#
## credit test
#SKIP: {
#  my $tx = new Business::OnlinePayment( "Litle", %opts );
#  $tx->content( %content, 'action' => "credit");
#  tx_check(
#    $tx,
#    desc          => "credit",
#    is_success    => 1,
#    result_code   => '000',
#    error_message => 'RETURN ACCEPTED',
#    authorization => qr/\d{6}/,
#    avs_code      => '',
#    cvv2_response => '',
#    );
#}


sub tx_check {
    my $tx = shift;
    my %o  = @_;

    $tx->test_transaction(1);
    $tx->submit;

    is( $tx->is_success,    $o{is_success},    "$o{desc}: " . tx_info($tx) );
    is( $tx->result_code,   $o{result_code},   "result_code(): RESULT" );
    is( $tx->error_message, $o{error_message}, "error_message() / RESPMSG" );
    like( $tx->authorization, $o{authorization}, "authorization() / AUTHCODE" );
    is( $tx->avs_code,  $o{avs_code},  "avs_code() / AVSADDR and AVSZIP" );
    is( $tx->cvv2_response, $o{cvv2_response}, "cvv2_response() / CVV2MATCH" );
    like( $tx->order_number, qr/^\w{18}/, "order_number() / PNREF" );
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
