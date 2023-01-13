#============================================================================================================
#
#	cookie管理モジュール
#
#============================================================================================================
package RADAGAST;

use strict;
#use warnings;
use Encode;

#------------------------------------------------------------------------------------------------------------
#
#	コンストラクタ
#	-------------------------------------------------------------------------------------
#	@param	なし
#	@return	モジュールオブジェクト
#
#------------------------------------------------------------------------------------------------------------
sub new
{
	my $class = shift;
	
	my $obj = {
		'COOKIE'	=> undef,
	};
	bless $obj, $class;
	
	return $obj;
}

#------------------------------------------------------------------------------------------------------------
#
#	cookie値取得
#	-------------------------------------------------------------------------------------
#	@param	なし
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub Init
{
	my $this = shift;
	
	$this->{'COOKIE'} = {};
	
	if ($ENV{'HTTP_COOKIE'}) {
		my @pairs = split(/;\s*/, $ENV{'HTTP_COOKIE'});
		foreach (@pairs) {
			my ($name, $value) = split(/=/, $_, 2);
			$value =~ s/^"|"$//g;
			$value =~ s/%([0-9A-Fa-f][0-9A-Fa-f])/pack('H2', $1)/eg;
			$this->{'COOKIE'}->{$name} = $value;
		}
		return 1;
	}
	return 0;
}
#------------------------------------------------------------------------------------------------------------
#
#	cookie値設定
#	-------------------------------------------------------------------------------------
#	@param	$key	キー
#	@param	$val	設定値
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub Set
{
	my $this = shift;
	my ($key, $val, $enc) = @_;
	
	Encode::from_to($val, 'sjis', $enc) if (defined $enc);
	$this->{'COOKIE'}->{$key} = $val;
}

#------------------------------------------------------------------------------------------------------------
#
#	cookie値取得
#	-------------------------------------------------------------------------------------
#	@param	$key	キー
#			$default : デフォルト
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub Get
{
	my $this = shift;
	my ($key, $default, $enc) = @_;
	
	my $val = $this->{'COOKIE'}->{$key};
	Encode::from_to($val, $enc, 'sjis') if (defined $val && defined $enc);
	
	return (defined $val ? $val : (defined $default ? $default : undef));
}

#------------------------------------------------------------------------------------------------------------
#
#	cookie値削除
#	-------------------------------------------------------------------------------------
#	@param	$key	キー
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub Delete
{
	my $this = shift;
	my ($key) = @_;
	
	delete $this->{'COOKIE'}->{$key};
}

#------------------------------------------------------------------------------------------------------------
#
#	cookie値存在確認
#	-------------------------------------------------------------------------------------
#	@param	$key	キー
#	@return	キーが存在したらtrue
#
#------------------------------------------------------------------------------------------------------------
sub IsExist
{
	my $this = shift;
	my ($key) = @_;
	
	return exists($this->{'COOKIE'}->{$key});
}

#------------------------------------------------------------------------------------------------------------
#
#	cookie出力
#	-------------------------------------------------------------------------------------
#	@param	$Page	出力モジュール
#	@param	$path	cookieパス
#	@param	$limit	有効期限
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub Out
{
	my $this = shift;
	my ($Page, $path, $limit) = @_;
	
	# 日付情報の設定
	my @gmt = gmtime(time + $limit * 60);
	my @week = qw(Sun Mon Tue Wed Thu Fri Sat);
	my @month = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
	
	# 有効期限文字列生成
	my $date = sprintf('%s, %02d-%s-%04d %02d:%02d:%02d GMT',
					$week[$gmt[6]], $gmt[3], $month[$gmt[4]], $gmt[5] + 1900,
					$gmt[2], $gmt[1], $gmt[0]);
	
	# 設定されているcookieを全て出力する
	foreach my $key (keys %{$this->{'COOKIE'}}) {
		my $value = $this->{'COOKIE'}->{$key};
		$value =~ s/([^\w])/'%'.unpack('H2', $1)/eg;
		$Page->Print("Set-Cookie: $key=\"$value\"; expires=$date; path=$path\n");
	}
}

#------------------------------------------------------------------------------------------------------------
#
#	cookie取得用javascript出力
#	-------------------------------------------------------------------------------------
#	@param	$Page	出力モジュール
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub Print
{
	my $this = shift;
	my ($Page) = @_;
	
	$Page->Print(<<JavaScript);
<script language="JavaScript" type="text/javascript">
<!--
function l(e) {
	var N = getCookie("NAME"), M = getCookie("MAIL");
	for (var i = 0, j = document.forms ; i < j.length ; i++){
		if (j[i].FROM && j[i].mail) {
			j[i].FROM.value = N;
			j[i].mail.value = M;
		}}
}
window.onload = l;
function getCookie(key) {
	var ptrn = '(?:^|;| )' + key + '="(.*?)"';
	if (document.cookie.match(ptrn))
		return decodeURIComponent(RegExp.\$1);
	return "";
}
//-->
</script>
JavaScript
}

#============================================================================================================
#	モジュール終端
#============================================================================================================
1;