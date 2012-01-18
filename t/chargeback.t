#!/usr/bin/perl -w

use Test::More qw(no_plan);
use Data::Dumper; 
## grab info from the ENV
my $login = $ENV{'BOP_USERNAME'} ? $ENV{'BOP_USERNAME'} : 'TESTMERCHANT';
my $password = $ENV{'BOP_PASSWORD'} ? $ENV{'BOP_PASSWORD'} : 'TESTPASS';
my $merchantid = $ENV{'BOP_MERCHANTID'} ? $ENV{'BOP_MERCHANTID'} : 'TESTMERCHANTID';

my @opts = ('default_Origin' => 'RECURRING');

my $str = do { local $/ = undef; <DATA> };
my $data;
eval($str);

my $authed = 
    $ENV{BOP_USERNAME}
    && $ENV{BOP_PASSWORD}
    && $ENV{BOP_MERCHANTID};

use_ok 'Business::OnlinePayment';

SKIP: {
    skip "No Auth Supplied", 3, !$authed;
    ok( $login, 'Supplied a Login' );
    ok( $password, 'Supplied a Password' );
    like( $merchantid, qr/^\d+/, 'MerchantID');
}

my %orig_content = (
    login          => $login,
    password       => $password,
    merchantid     => $merchantid,
);

my $chargeback_list;

SKIP: {
    skip "No Test Account setup",1 if ! $authed;
    ### list test
    print '-'x70;
    print "CHARGEBACK LIST TESTS\n";
    my $tx = Business::OnlinePayment->new("Litle", @opts);
    $tx->test_transaction(1);
    $chargeback_list = $tx->chargeback_activity_request( {
        login      => $login,
        password   => $password,
        merchantid => $merchantid,
        date       => '2012-01-16',
      });
    is( $tx->is_success, 1, "Chargeback list request" );
}

diag("HTTPS POST");
SKIP: {
    skip "No Test Account setup",54 if ! $authed;
### Litle Updater Tests
    print '-'x70;
    print "Update TESTS\n";
    is( scalar(@{$chargeback_list}) == 4, 1, "Objectified all four test cases" );

    foreach my $resp ( @{ $chargeback_list } ) {
        my ($resp_validation) = grep { ($merchantid . $_->{'id'}) ==  $resp->case_id } @{ $data->{'list_response'} };
        response_check(
            $resp,
            desc        => 'List Response Check',
            reason_code => $resp_validation->{'reasonCode'},
            reason_code_description =>
              $resp_validation->{'reasonCodeDescription'},
            type => $resp_validation->{'chargebackType'},
        );
    }

}


#-----------------------------------------------------------------------------------
#
sub tx_check {
    my $tx = shift;
    my %o  = @_;

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
    like( $tx->order_number, qr/^\w{5,19}/, "order_number() / PNREF" );
}

#
sub response_check {
    my $tx = shift;
    my %o  = @_;

    is( $tx->reason_code,   $o{reason_code},   "reason_code(): RESULT" );
    is( $tx->reason_code_description,   $o{reason_code_description},   "reason_code_description(): RESULT" );
    is( $tx->hash->{'chargebackType'}, $o{type}, "type() / RESPMSG" );
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
            " invoice_number(",   $tx->invoice_number ,   ")",
        )
    );
}

sub expiration_date {
    my($month, $year) = (localtime)[4,5];
    $year++;       # So we expire next year.
    $year %= 100;  # y2k?  What's that?

    return sprintf("%02d%02d", $month, $year);
}

__DATA__
$data= {
'list_response' => [
    {
        id                      => '001',
        'chargebackType'        => 'Deposit',
        'reasonCodeDescription' => 'First Chargeback -- Test Transaction',
        'reasonCode'            => '00A1',
    },
{
    id                      => '002',
    'fromQueue'             => 'Merchant',
    'chargebackType'        => 'Deposit',
    'reasonCodeDescription' => 'First Chargeback -- Test Transaction',
    'reasonCode'            => '00A1',
},
  {
    id                      => '003',
    'chargebackType'        => 'Deposit',
    'reasonCodeDescription' => 'First Chargeback -- Test Transaction',
    'reasonCode'            => '00A1',
  },
  {
    id                        => '004',
    'fromQueue'               => 'Merchant',
    'chargebackType'          => 'Deposit',
    'reasonCodeDescription'   => 'First Chargeback -- Test Transaction',
    'reasonCode'              => '00A1',
  },
  ],
        };
