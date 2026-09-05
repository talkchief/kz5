%% TEST STUB ONLY. Never copy this module to any runtime directory.
-module(kz_datamgr).
-export([open_cache_doc/2,get_results/3]).
open_cache_doc(Db,Id) -> (get({fake_datamgr,open}))(Db,Id).
get_results(Db,View,Options) -> (get({fake_datamgr,view}))(Db,View,Options).
