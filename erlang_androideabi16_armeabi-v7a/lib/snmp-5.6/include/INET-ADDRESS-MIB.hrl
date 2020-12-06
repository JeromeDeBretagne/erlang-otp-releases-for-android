%%% This file was automatically generated by snmpc_mib_to_hrl version 5.6
%%% Date: 23-Jul-2020::23:40:57
-ifndef('INET-ADDRESS-MIB').
-define('INET-ADDRESS-MIB', true).

%% Oids

-define(inetAddressMIB, [1,3,6,1,2,1,76]).


%% Range values


%% Definitions from 'InetVersion'
-define('InetVersion_ipv6', 2).
-define('InetVersion_ipv4', 1).
-define('InetVersion_unknown', 0).

%% Definitions from 'InetScopeType'
-define('InetScopeType_global', 14).
-define('InetScopeType_organizationLocal', 8).
-define('InetScopeType_siteLocal', 5).
-define('InetScopeType_adminLocal', 4).
-define('InetScopeType_subnetLocal', 3).
-define('InetScopeType_linkLocal', 2).
-define('InetScopeType_interfaceLocal', 1).

%% Definitions from 'InetAddressType'
-define('InetAddressType_dns', 16).
-define('InetAddressType_ipv6z', 4).
-define('InetAddressType_ipv4z', 3).
-define('InetAddressType_ipv6', 2).
-define('InetAddressType_ipv4', 1).
-define('InetAddressType_unknown', 0).

%% Default values

-endif.
