INCLUDES = -I$(top_srcdir) -I$(includedir) $(NETSPEED_CFLAGS) $(NETSPEED_LIBGTOP_CFLAGS) \
       -DMATELOCALEDIR=\""$(datadir)/locale"\" \
       -DDATADIR=\""$(datadir)/"\" \
       -DPREFIX=\""$(prefix)/"\" \
       -DLIBDIR=\""$(libdir)/"\" \
       -DSYSCONFDIR=\""$(sysconfdir)/"\"

libexec_PROGRAMS = mate_netspeed_applet2

mate_netspeed_applet2_SOURCES = backend.h backend.c netspeed.c

mate_netspeed_applet2_LDADD = $(NETSPEED_LIBS) $(NETSPEED_LIBGTOP_LIBS) $(IWLIB) $(INTLLIBS)
