package CGI::Session::Serialize::storable;use strict;use Storable;require CGI::Session::ErrorHandler;$CGI::Session::Serialize::storable::VERSION='4.43';@CGI::Session::Serialize::storable::ISA=("CGI::Session::ErrorHandler");sub freeze{my($self,$data)=@_;return Storable::freeze($data);}sub thaw{my($self,$string)=@_;return Storable::thaw($string);}1;