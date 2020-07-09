# Introduction

This is a plugin for [Koha](http://koha-community.org) which enables the use of Capita Pay360 for online payments.

# Downloading


# Installing

## Enable the plugin system

To set up the Koha plugin system you must first make some changes to your install.

* Change `<enable_plugins>0<enable_plugins>` to `<enable_plugins>1</enable_plugins>` in your koha-conf.xml file
* Confirm that the path to `<pluginsdir>` exists, is correct, and is writable by the web server
* Add the pluginsdir to your apache PERL5LIB paths and koha-plack startup scripts PERL5LIB
* You will need to add the following to the apache config for your site:

```
   Alias /plugin/ "/var/lib/koha/kohadev/plugins/"
   # The stanza below is needed for Apache 2.4+
   <Directory /var/lib/koha/kohadev/plugins/>
         Options Indexes FollowSymLinks
         AllowOverride None
         Require all granted
         Options +ExecCGI
         AddHandler cgi-script .pl
    </Directory>
```

* Restart your webserver

Once set up is complete you will need to alter your UseKohaPlugins system preference. On the Tools page you will see the Tools Plugins and on the Reports page you will see the Reports Plugins.

## Dependancies

This plugin has some additional perl library dependancies which are not part of the standard Koha install and as such you will need to install them in your prefered manor:

* XML::Compile::WSDL11
* XML::Compile::SOAP
* XML::Compile::Transport::SOAPHTTP
* Time::Moment

`sudo apt install libxml-compile-wsdl11-perl libdata-guid-perl libtime-moment-perl` for example

## Download and install the plugin

The latest releases of this plugin can be obtained from the [release page](https://github.com/ptfs-europe/koha-plugin-capita-payments/releases) where you can download the relevant *.kpz file

# Setup

The available configuration options are all accessible from inside the staff client under 'Home › Tools › Plugins'

