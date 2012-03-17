 /*  netspeed.c
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Library General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *
 *  Netspeed Applet was writen by Jörgen Scheibengruber <mfcn@gmx.de>
 * 
 *  Mate Netspeed Applet migrated by Stefano Karapetsas <stefano@karapetsas.com>
 */

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif 

#include <math.h>
#include <gtk/gtk.h>
#include <mate-panel-applet.h>
#include <mate-panel-applet-mateconf.h>
#include <mateconf/mateconf-client.h>
#include "backend.h"

 /* Icons for the interfaces */
static const char* const dev_type_icon[DEV_UNKNOWN + 1] = {
	"mate-netspeed-loopback",    /* DEV_LO */
	"network-wired",             /* DEV_ETHERNET */
	"network-wireless",          /* DEV_WIRELESS */
	"mate-netspeed-ppp",         /* DEV_PPP */
	"mate-netspeed-plip",        /* DEV_PLIP */
	"mate-netspeed-plip",        /* DEV_SLIP */
	"network-workgroup",         /* DEV_UNKNOWN */
};

static const char* wireless_quality_icon[] = {
	"mate-netspeed-wireless-25",
	"mate-netspeed-wireless-50",
	"mate-netspeed-wireless-75",
	"mate-netspeed-wireless-100"
};

static const char IN_ICON[] = "stock_navigate-next";
static const char OUT_ICON[] = "stock_navigate-prev";
static const char ERROR_ICON[] = "gtk-dialog-error";
static const char LOGO_ICON[] = "mate-netspeed-applet";

/* How many old in out values do we store?
 * The value actually shown in the applet is the average
 * of these values -> prevents the value from
 * "jumping around like crazy"
 */
#define OLD_VALUES 5
#define GRAPH_VALUES 180
#define GRAPH_LINES 4

/* A struct containing all the "global" data of the 
 * applet
 */
typedef struct
{
	MatePanelApplet *applet;
	GtkWidget *box, *pix_box,
	*in_box, *in_label, *in_pix,
	*out_box, *out_label, *out_pix,
	*sum_box, *sum_label, *dev_pix, *qual_pix;
	GdkPixbuf *qual_pixbufs[4];
	
	GtkWidget *signalbar;
	
	gboolean labels_dont_shrink;
	
	DevInfo devinfo;
	gboolean device_has_changed;
		
	guint timeout_id;
	int refresh_time;
	char *up_cmd, *down_cmd;
	gboolean show_sum, show_bits;
	gboolean change_icon, auto_change_device;
	GdkColor in_color, out_color;
	int width;
	
	GtkWidget *inbytes_text, *outbytes_text;
	GtkDialog *details, *settings;
	GtkDrawingArea *drawingarea;
	GtkWidget *network_device_combo;
	
	guint index_old;
	guint64 in_old[OLD_VALUES], out_old[OLD_VALUES];
	double max_graph, in_graph[GRAPH_VALUES], out_graph[GRAPH_VALUES];
	int index_graph;
	
	GtkWidget *connect_dialog;
	
	gboolean show_tooltip;
} MateNetspeedApplet;

static const char 
mate_netspeed_applet_menu_xml [] =
	"<popup name=\"button3\">\n"
	"   <menuitem name=\"Properties Item\" verb=\"MateNetspeedAppletDetails\" label=\"%s\"\n"
	"             pixtype=\"stock\" pixname=\"gtk-info\"/>\n"
	"   <separator/>\n"
	"   <menuitem name=\"Properties Item\" verb=\"MateNetspeedAppletProperties\" label=\"%s\"\n"
	"             pixtype=\"stock\" pixname=\"gtk-properties\"/>\n"
	"   <menuitem name=\"Help Item\" verb=\"MateNetspeedAppletHelp\" label=\"%s\"\n"
	"             pixtype=\"stock\" pixname=\"gtk-help\"/>\n"
	"   <menuitem name=\"About Item\" verb=\"MateNetspeedAppletAbout\" label=\"%s\"\n"
	"             pixtype=\"stock\" pixname=\"gtk-about\"/>\n"
	"</popup>\n";


static void
update_tooltip(MateNetspeedApplet* applet);

static void
device_change_cb(GtkComboBox *combo, MateNetspeedApplet *applet);

static gboolean
open_uri (GtkWidget *parent, const char *url, GError **error)
{
	gboolean ret;
	char *cmdline;
	GdkScreen *screen;

	screen = gtk_widget_get_screen (parent);
	cmdline = g_strconcat ("xdg-open ", url, NULL);
	ret = gdk_spawn_command_line_on_screen (screen, cmdline, error);
	g_free (cmdline);

	return ret;
}

/* Adds a Pango markup "size" to a bytestring
 */
static void
add_markup_size(char **string, int size)
{
	char *tmp = *string;
	*string = g_strdup_printf("<span size=\"%d\">%s</span>", size * 1000, tmp);
	g_free(tmp);
}

/* Adds a Pango markup "foreground" to a bytestring
 */
static void
add_markup_fgcolor(char **string, const char *color)
{
	char *tmp = *string;
	*string = g_strdup_printf("<span foreground=\"%s\">%s</span>", color, tmp);
	g_free(tmp);
}

/* Here some rearangement of the icons and the labels occurs
 * according to the panelsize and wether we show in and out
 * or just the sum
 */
static void
applet_change_size_or_orient(MatePanelApplet *applet_widget, int arg1, MateNetspeedApplet *applet)
{
	int size;
	MatePanelAppletOrient orient;
	
	g_assert(applet);
	
	size = mate_panel_applet_get_size(applet_widget);
	orient = mate_panel_applet_get_orient(applet_widget);
	
	gtk_widget_ref(applet->pix_box);
	gtk_widget_ref(applet->in_pix);
	gtk_widget_ref(applet->in_label);
	gtk_widget_ref(applet->out_pix);
	gtk_widget_ref(applet->out_label);
	gtk_widget_ref(applet->sum_label);

	if (applet->in_box) {
		gtk_container_remove(GTK_CONTAINER(applet->in_box), applet->in_label);
		gtk_container_remove(GTK_CONTAINER(applet->in_box), applet->in_pix);
		gtk_widget_destroy(applet->in_box);
	}
	if (applet->out_box) {
		gtk_container_remove(GTK_CONTAINER(applet->out_box), applet->out_label);
		gtk_container_remove(GTK_CONTAINER(applet->out_box), applet->out_pix);
		gtk_widget_destroy(applet->out_box);
	}
	if (applet->sum_box) {
		gtk_container_remove(GTK_CONTAINER(applet->sum_box), applet->sum_label);
		gtk_widget_destroy(applet->sum_box);
	}
	if (applet->box) {
		gtk_container_remove(GTK_CONTAINER(applet->box), applet->pix_box);
		gtk_widget_destroy(applet->box);
	}
		
	if (orient == MATE_PANEL_APPLET_ORIENT_LEFT || orient == MATE_PANEL_APPLET_ORIENT_RIGHT) {
		applet->box = gtk_vbox_new(FALSE, 0);
		if (size > 64) {
			applet->sum_box = gtk_hbox_new(FALSE, 2);
			applet->in_box = gtk_hbox_new(FALSE, 1);
			applet->out_box = gtk_hbox_new(FALSE, 1);
		} else {	
			applet->sum_box = gtk_vbox_new(FALSE, 0);
			applet->in_box = gtk_vbox_new(FALSE, 0);
			applet->out_box = gtk_vbox_new(FALSE, 0);
		}
		applet->labels_dont_shrink = FALSE;
	} else {
		applet->in_box = gtk_hbox_new(FALSE, 1);
		applet->out_box = gtk_hbox_new(FALSE, 1);
		if (size < 48) {
			applet->sum_box = gtk_hbox_new(FALSE, 2);
			applet->box = gtk_hbox_new(FALSE, 1);
			applet->labels_dont_shrink = TRUE;
		} else {
			applet->sum_box = gtk_vbox_new(FALSE, 0);
			applet->box = gtk_vbox_new(FALSE, 0);
			applet->labels_dont_shrink = !applet->show_sum;
		}
	}		
	
	gtk_box_pack_start(GTK_BOX(applet->in_box), applet->in_pix, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(applet->in_box), applet->in_label, TRUE, TRUE, 0);
	gtk_box_pack_start(GTK_BOX(applet->out_box), applet->out_pix, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(applet->out_box), applet->out_label, TRUE, TRUE, 0);
	gtk_box_pack_start(GTK_BOX(applet->sum_box), applet->sum_label, TRUE, TRUE, 0);
	gtk_box_pack_start(GTK_BOX(applet->box), applet->pix_box, FALSE, FALSE, 0);
	
	gtk_widget_unref(applet->pix_box);
	gtk_widget_unref(applet->in_pix);
	gtk_widget_unref(applet->in_label);
	gtk_widget_unref(applet->out_pix);
	gtk_widget_unref(applet->out_label);
	gtk_widget_unref(applet->sum_label);

	if (applet->show_sum) {
		gtk_box_pack_start(GTK_BOX(applet->box), applet->sum_box, TRUE, TRUE, 0);
	} else {
		gtk_box_pack_start(GTK_BOX(applet->box), applet->in_box, TRUE, TRUE, 0);
		gtk_box_pack_start(GTK_BOX(applet->box), applet->out_box, TRUE, TRUE, 0);
	}		
	
	gtk_widget_show_all(applet->box);
	gtk_container_add(GTK_CONTAINER(applet->applet), applet->box);
}

/* Change the background of the applet according to
 * the panel background.
 */
static void 
change_background_cb(MatePanelApplet *applet_widget, 
				MatePanelAppletBackgroundType type,
				GdkColor *color, GdkPixmap *pixmap, 
				MateNetspeedApplet *applet)
{
	GtkStyle *style;
	GtkRcStyle *rc_style = gtk_rc_style_new ();
	gtk_widget_set_style (GTK_WIDGET (applet_widget), NULL);
	gtk_widget_modify_style (GTK_WIDGET (applet_widget), rc_style);
	gtk_rc_style_unref (rc_style);

	switch (type) {
		case PANEL_PIXMAP_BACKGROUND:
			style = gtk_style_copy (GTK_WIDGET (applet_widget)->style);
			if(style->bg_pixmap[GTK_STATE_NORMAL])
				g_object_unref (style->bg_pixmap[GTK_STATE_NORMAL]);
			style->bg_pixmap[GTK_STATE_NORMAL] = g_object_ref (pixmap);
			gtk_widget_set_style (GTK_WIDGET(applet_widget), style);
			g_object_unref (style);
			break;

		case PANEL_COLOR_BACKGROUND:
			gtk_widget_modify_bg(GTK_WIDGET(applet_widget), GTK_STATE_NORMAL, color);
			break;

		case PANEL_NO_BACKGROUND:
			break;
	}
}


/* Change the icons according to the selected device
 */
static void
change_icons(MateNetspeedApplet *applet)
{
	GdkPixbuf *dev, *down;
	GdkPixbuf *in_arrow, *out_arrow;
	GtkIconTheme *icon_theme;
	
	icon_theme = gtk_icon_theme_get_default();
	/* If the user wants a different icon then the eth0, we load it */
	if (applet->change_icon) {
		dev = gtk_icon_theme_load_icon(icon_theme, 
                        dev_type_icon[applet->devinfo.type], 16, 0, NULL);
	} else {
        	dev = gtk_icon_theme_load_icon(icon_theme, 
					       dev_type_icon[DEV_UNKNOWN], 
					       16, 0, NULL);
	}
    
    	/* We need a fallback */
    	if (dev == NULL) 
		dev = gtk_icon_theme_load_icon(icon_theme, 
					       dev_type_icon[DEV_UNKNOWN],
					       16, 0, NULL);
        
    
	in_arrow = gtk_icon_theme_load_icon(icon_theme, IN_ICON, 16, 0, NULL);
	out_arrow = gtk_icon_theme_load_icon(icon_theme, OUT_ICON, 16, 0, NULL);

	/* Set the windowmanager icon for the applet */
	gtk_window_set_default_icon_name(LOGO_ICON);

	gtk_image_set_from_pixbuf(GTK_IMAGE(applet->out_pix), out_arrow);
	gtk_image_set_from_pixbuf(GTK_IMAGE(applet->in_pix), in_arrow);
	gdk_pixbuf_unref(in_arrow);
	gdk_pixbuf_unref(out_arrow);
	
	if (applet->devinfo.running) {
		gtk_widget_show(applet->in_box);
		gtk_widget_show(applet->out_box);
	} else {
		GdkPixbuf *copy;
		gtk_widget_hide(applet->in_box);
		gtk_widget_hide(applet->out_box);

		/* We're not allowed to modify "dev" */
        	copy = gdk_pixbuf_copy(dev);
        
        	down = gtk_icon_theme_load_icon(icon_theme, ERROR_ICON, 16, 0, NULL);	
		gdk_pixbuf_composite(down, copy, 8, 8, 8, 8, 8, 8, 0.5, 0.5, GDK_INTERP_BILINEAR, 0xFF);
		g_object_unref(down);
	      	g_object_unref(dev);
		dev = copy;
	}		

	gtk_image_set_from_pixbuf(GTK_IMAGE(applet->dev_pix), dev);
	g_object_unref(dev);
}

static void
update_quality_icon(MateNetspeedApplet *applet)
{
	unsigned int q;
	
	q = (applet->devinfo.qual);
	q = logf (q / 3.0f) + 0.25f;

	g_assert(q >= 0 && q < 4);
	gtk_image_set_from_pixbuf (GTK_IMAGE(applet->qual_pix), applet->qual_pixbufs[q]);
}

static void
init_quality_pixbufs(MateNetspeedApplet *applet)
{
	GtkIconTheme *icon_theme;
	int i;
	
	icon_theme = gtk_icon_theme_get_default();

	for (i = 0; i < 4; i++) {
		if (applet->qual_pixbufs[i])
			g_object_unref(applet->qual_pixbufs[i]);
		applet->qual_pixbufs[i] = gtk_icon_theme_load_icon(icon_theme, 
			wireless_quality_icon[i], 24, 0, NULL);
	}
}


static void
icon_theme_changed_cb(GtkIconTheme *icon_theme, gpointer user_data)
{
    init_quality_pixbufs(user_data);
    update_quality_icon(user_data);
    change_icons(user_data);
}    

/* Converts a number of bytes into a human
 * readable string - in [M/k]bytes[/s]
 * The string has to be freed
 */
static char* 
bytes_to_string(double bytes, gboolean per_sec, gboolean bits)
{
	const char *format;
	const char *unit;
	guint kilo; /* no really a kilo : a kilo or kibi */

	if (bits) {
		bytes *= 8;
		kilo = 1000;
	} else
		kilo = 1024;

	if (bytes < kilo) {

		format = "%.0f %s";

		if (per_sec)
			unit = bits ? N_("b/s")   : N_("B/s");
		else
			unit = bits ? N_("bits")  : N_("bytes");

	} else if (bytes < (kilo * kilo)) {
		format = (bytes < (100 * kilo)) ? "%.1f %s" : "%.0f %s";
		bytes /= kilo;

		if (per_sec)
			unit = bits ? N_("kb/s") : N_("KiB/s");
		else
			unit = bits ? N_("kb")   : N_("KiB");

	} else {

		format = "%.1f %s";

		bytes /= kilo * kilo;

		if (per_sec)
			unit = bits ? N_("Mb/s") : N_("MiB/s");
		else
			unit = bits ? N_("Mb")   : N_("MiB");
	}

	return g_strdup_printf(format, bytes, gettext(unit));
}


/* Redraws the graph drawingarea
 * Some really black magic is going on in here ;-)
 */
static void
redraw_graph(MateNetspeedApplet *applet)
{
	GdkGC *gc;
	GdkColor color;
	GtkWidget *da = GTK_WIDGET(applet->drawingarea);
	GdkWindow *window, *real_window = da->window;
	GdkRectangle ra;
	GtkStateType state;
	GdkPoint in_points[GRAPH_VALUES], out_points[GRAPH_VALUES];
	PangoLayout *layout;
	PangoRectangle logical_rect;
	char *text; 
	int i, offset, w, h;
	double max_val;
	
	gc = gdk_gc_new (real_window);
	gdk_drawable_get_size(real_window, &w, &h);

	/* use doublebuffering to avoid flickering */
	window = gdk_pixmap_new(real_window, w, h, -1);
	
	/* the graph hight should be: hight/2 <= applet->max_graph < hight */
	for (max_val = 1; max_val < applet->max_graph; max_val *= 2) ;
	
	/* calculate the polygons (GdkPoint[]) for the graphs */ 
	offset = 0;
	for (i = applet->index_graph + 1; applet->in_graph[i] < 0; i = (i + 1) % GRAPH_VALUES)
		offset++;
	for (i = offset + 1; i < GRAPH_VALUES; i++)
	{
		int index = (applet->index_graph + i) % GRAPH_VALUES;
		out_points[i].x = in_points[i].x = ((w - 8) * i) / GRAPH_VALUES + 2;
		in_points[i].y = h - 6 - (int)((h - 8) * applet->in_graph[index] / max_val);
		out_points[i].y = h - 6 - (int)((h - 8) * applet->out_graph[index] / max_val);
	}	
	in_points[offset].x = out_points[offset].x = ((w - 8) * offset) / GRAPH_VALUES + 2;
	in_points[offset].y = in_points[offset + 1].y;
	out_points[offset].y = out_points[offset + 1].y;
	
	/* draw the background */
	gdk_gc_set_rgb_fg_color (gc, &da->style->black);
	gdk_draw_rectangle (window, gc, TRUE, 0, 0, w, h);
	
	color.red = 0x3a00; color.green = 0x8000; color.blue = 0x1400;
	gdk_gc_set_rgb_fg_color(gc, &color);
	gdk_draw_rectangle (window, gc, FALSE, 2, 2, w - 6, h - 6);
	
	for (i = 0; i < GRAPH_LINES; i++) {
		int y = 2 + ((h - 6) * i) / GRAPH_LINES; 
		gdk_draw_line(window, gc, 2, y, w - 4, y);
	}
	
	/* draw the polygons */
	gdk_gc_set_line_attributes(gc, 2, GDK_LINE_SOLID, GDK_CAP_ROUND, GDK_JOIN_ROUND);
	gdk_gc_set_rgb_fg_color(gc, &applet->in_color);
	gdk_draw_lines(window, gc, in_points + offset, GRAPH_VALUES - offset);
	gdk_gc_set_rgb_fg_color(gc, &applet->out_color);
	gdk_draw_lines(window, gc, out_points + offset, GRAPH_VALUES - offset);

	/* draw the 2 labels */
	state = GTK_STATE_NORMAL;
	ra.x = 0; ra.y = 0;
	ra.width = w; ra.height = h;
	
	text = bytes_to_string(max_val, TRUE, applet->show_bits);
	add_markup_fgcolor(&text, "white");
	layout = gtk_widget_create_pango_layout (da, NULL);
	pango_layout_set_markup(layout, text, -1);
	g_free (text);
	gtk_paint_layout(da->style, window, state,	FALSE, &ra, da, "max_graph", 3, 2, layout);
	g_object_unref(G_OBJECT(layout));

	text = bytes_to_string(0.0, TRUE, applet->show_bits);
	add_markup_fgcolor(&text, "white");
	layout = gtk_widget_create_pango_layout (da, NULL);
	pango_layout_set_markup(layout, text, -1);
	pango_layout_get_pixel_extents (layout, NULL, &logical_rect);
	g_free (text);
	gtk_paint_layout(da->style, window, state,	FALSE, &ra, da, "max_graph", 3, h - 4 - logical_rect.height, layout);
	g_object_unref(G_OBJECT(layout));

	/* draw the pixmap to the real window */	
	gdk_draw_drawable(real_window, gc, window, 0, 0, 0, 0, w, h);
	
	g_object_unref(G_OBJECT(gc));
	g_object_unref(G_OBJECT(window));
}


static gboolean
set_applet_devinfo(MateNetspeedApplet* applet, const char* iface)
{
	DevInfo info;

	get_device_info(iface, &info);

	if (info.running) {
		free_device_info(&applet->devinfo);
		applet->devinfo = info;
		applet->device_has_changed = TRUE;
		return TRUE;
	}

	free_device_info(&info);
	return FALSE;
}

/* Find the first available device, that is running and != lo */
static void
search_for_up_if(MateNetspeedApplet *applet)
{
	const gchar *default_route;
	GList *devices, *tmp;
	DevInfo info;
	
	default_route = get_default_route();
    
	if (default_route != NULL) {
		if (set_applet_devinfo(applet, default_route))
			return;
	}

	devices = get_available_devices();
	for (tmp = devices; tmp; tmp = g_list_next(tmp)) {
		if (is_dummy_device(tmp->data))
			continue;
		if (set_applet_devinfo(applet, tmp->data))
			break;
	}
	free_devices_list(devices);
}

/* Here happens the really interesting stuff */
static void
update_applet(MateNetspeedApplet *applet)
{
	guint64 indiff, outdiff;
	double inrate, outrate;
	char *inbytes, *outbytes;
	int i;
	DevInfo oldinfo;
	
	if (!applet)	return;
	
	/* First we try to figure out if the device has changed */
	oldinfo = applet->devinfo;
	get_device_info(oldinfo.name, &applet->devinfo);
	if (compare_device_info(&applet->devinfo, &oldinfo))
		applet->device_has_changed = TRUE;
	free_device_info(&oldinfo);

	/* If the device has changed, reintialize stuff */	
	if (applet->device_has_changed) {
		change_icons(applet);
		if (applet->devinfo.type == DEV_WIRELESS &&
			applet->devinfo.up) {
			gtk_widget_show(applet->qual_pix);
		} else {
			gtk_widget_hide(applet->qual_pix);
		}	
		for (i = 0; i < OLD_VALUES; i++)
		{
			applet->in_old[i] = applet->devinfo.rx;
			applet->out_old[i] = applet->devinfo.tx;
		}
		for (i = 0; i < GRAPH_VALUES; i++)
		{
			applet->in_graph[i] = -1;
			applet->out_graph[i] = -1;
		}
		applet->max_graph = 0;
		applet->index_graph = 0;
		applet->device_has_changed = FALSE;
	}
		
	/* create the strings for the labels and tooltips */
	if (applet->devinfo.running)
	{	
		if (applet->devinfo.rx < applet->in_old[applet->index_old]) indiff = 0;
		else indiff = applet->devinfo.rx - applet->in_old[applet->index_old];
		if (applet->devinfo.tx < applet->out_old[applet->index_old]) outdiff = 0;
		else outdiff = applet->devinfo.tx - applet->out_old[applet->index_old];
		
		inrate = indiff * 1000.0;
		inrate /= (double)(applet->refresh_time * OLD_VALUES);
		outrate = outdiff * 1000.0;
		outrate /= (double)(applet->refresh_time * OLD_VALUES);
		
		applet->in_graph[applet->index_graph] = inrate;
		applet->out_graph[applet->index_graph] = outrate;
		applet->max_graph = MAX(inrate, applet->max_graph);
		applet->max_graph = MAX(outrate, applet->max_graph);
		
		applet->devinfo.rx_rate = bytes_to_string(inrate, TRUE, applet->show_bits);
		applet->devinfo.tx_rate = bytes_to_string(outrate, TRUE, applet->show_bits);
		applet->devinfo.sum_rate = bytes_to_string(inrate + outrate, TRUE, applet->show_bits);
	} else {
		applet->devinfo.rx_rate = g_strdup("");
		applet->devinfo.tx_rate = g_strdup("");
		applet->devinfo.sum_rate = g_strdup("");
		applet->in_graph[applet->index_graph] = 0;
		applet->out_graph[applet->index_graph] = 0;
	}
	
	if (applet->devinfo.type == DEV_WIRELESS) {
		if (applet->devinfo.up)
			update_quality_icon(applet);
		
		if (applet->signalbar) {
			float quality;
			char *text;

			quality = applet->devinfo.qual / 100.0f;
			if (quality > 1.0)
				quality = 1.0;

			text = g_strdup_printf ("%d %%", applet->devinfo.qual);
			gtk_progress_bar_set_fraction (GTK_PROGRESS_BAR (applet->signalbar), quality);
			gtk_progress_bar_set_text (GTK_PROGRESS_BAR (applet->signalbar), text);
			g_free(text);
		}
	}

	update_tooltip(applet);

	/* Refresh the text of the labels and tooltip */
	if (applet->show_sum) {
		gtk_label_set_markup(GTK_LABEL(applet->sum_label), applet->devinfo.sum_rate);
	} else {
		gtk_label_set_markup(GTK_LABEL(applet->in_label), applet->devinfo.rx_rate);
		gtk_label_set_markup(GTK_LABEL(applet->out_label), applet->devinfo.tx_rate);
	}

	/* Refresh the values of the Infodialog */
	if (applet->inbytes_text) {
		inbytes = bytes_to_string((double)applet->devinfo.rx, FALSE, applet->show_bits);
		gtk_label_set_text(GTK_LABEL(applet->inbytes_text), inbytes);
		g_free(inbytes);
	}	
	if (applet->outbytes_text) {
		outbytes = bytes_to_string((double)applet->devinfo.tx, FALSE, applet->show_bits);
		gtk_label_set_text(GTK_LABEL(applet->outbytes_text), outbytes);
		g_free(outbytes);
	}
	/* Redraw the graph of the Infodialog */
	if (applet->drawingarea)
		redraw_graph(applet);
	
	/* Save old values... */
	applet->in_old[applet->index_old] = applet->devinfo.rx;
	applet->out_old[applet->index_old] = applet->devinfo.tx;
	applet->index_old = (applet->index_old + 1) % OLD_VALUES;

	/* Move the graphindex. Check if we can scale down again */
	applet->index_graph = (applet->index_graph + 1) % GRAPH_VALUES; 
	if (applet->index_graph % 20 == 0)
	{
		double max = 0;
		for (i = 0; i < GRAPH_VALUES; i++)
		{
			max = MAX(max, applet->in_graph[i]);
			max = MAX(max, applet->out_graph[i]);
		}
		applet->max_graph = max;
	}

	/* Always follow the default route */
	if (applet->auto_change_device) {
		gboolean change_device_now = !applet->devinfo.running;
		if (!change_device_now) {
			const gchar *default_route;
			default_route = get_default_route();
			change_device_now = (default_route != NULL
						&& strcmp(default_route,
							applet->devinfo.name));
		}
		if (change_device_now) {
			search_for_up_if(applet);
		}
	}
}

static gboolean
timeout_function(MateNetspeedApplet *applet)
{
	if (!applet)
		return FALSE;
	if (!applet->timeout_id)
		return FALSE;

	update_applet(applet);
	return TRUE;
}

/* Display a section of netspeed help
 */
static void
display_help (GtkWidget *dialog, const gchar *section)
{
	GError *error = NULL;
	gboolean ret;
	char *uri;

	if (section)
		uri = g_strdup_printf ("ghelp:mate_netspeed_applet?%s", section);
	else
		uri = g_strdup ("ghelp:mate_netspeed_applet");

	ret = open_uri (dialog, uri, &error);
	g_free (uri);
	if (ret == FALSE) {
		GtkWidget *error_dialog = gtk_message_dialog_new (NULL,
								  GTK_DIALOG_MODAL,
								  GTK_MESSAGE_ERROR,
								  GTK_BUTTONS_OK,
								  _("There was an error displaying help:\n%s"),
								  error->message);
		g_signal_connect (error_dialog, "response",
				  G_CALLBACK (gtk_widget_destroy), NULL);
	       
		gtk_window_set_resizable (GTK_WINDOW (error_dialog), FALSE);
		gtk_window_set_screen  (GTK_WINDOW (error_dialog), gtk_widget_get_screen (dialog));
		gtk_widget_show (error_dialog);
		g_error_free (error);
	}
}

/* Opens gnome help application
 */
static void
help_cb (MateComponentUIComponent *uic, MateNetspeedApplet *ap, const gchar *verbname)
{
	display_help (GTK_WIDGET (ap->applet), NULL);
}

enum {
	LINK_TYPE_EMAIL,
	LINK_TYPE_URL
};

/* handle the links of the about dialog */
static void
handle_links (GtkAboutDialog *about, const gchar *link, gpointer data)
{
	gchar *new_link;
	GError *error = NULL;
	gboolean ret;
	GtkWidget *dialog;

	switch (GPOINTER_TO_INT (data)){
	case LINK_TYPE_EMAIL:
		new_link = g_strdup_printf ("mailto:%s", link);
		break;
	case LINK_TYPE_URL:
		new_link = g_strdup (link);
		break;
	default:
		g_assert_not_reached ();
	}

	ret = open_uri (GTK_WIDGET (about), new_link, &error);

	if (ret == FALSE) {
    		dialog = gtk_message_dialog_new (GTK_WINDOW (dialog), 
						 GTK_DIALOG_DESTROY_WITH_PARENT, 
						 GTK_MESSAGE_ERROR, GTK_BUTTONS_OK, 
				                 _("Failed to show:\n%s"), new_link); 
    		gtk_dialog_run (GTK_DIALOG (dialog));
    		gtk_widget_destroy (dialog);
		g_error_free(error);
	}
	g_free (new_link);
}

/* Just the about window... If it's already open, just fokus it
 */
static void
about_cb(MateComponentUIComponent *uic, gpointer data, const gchar *verbname)
{
	const char *authors[] = 
	{
		"Jörgen Scheibengruber <mfcn@gmx.de>", 
		"Dennis Cranston <dennis_cranston@yahoo.com>",
		"Pedro Villavicencio Garrido <pvillavi@gnome.org>",
		"Benoît Dejean <benoit@placenet.org>",
		"Stefano Karapetsas <stefano@karapetsas.com>",
		"Perberos <perberos@gmail.com>",
		NULL
	};
    
	gtk_about_dialog_set_email_hook ((GtkAboutDialogActivateLinkFunc) handle_links,
					 GINT_TO_POINTER (LINK_TYPE_EMAIL), NULL);
	
	gtk_about_dialog_set_url_hook ((GtkAboutDialogActivateLinkFunc) handle_links,
				       GINT_TO_POINTER (LINK_TYPE_URL), NULL);
	
	gtk_show_about_dialog (NULL, 
			       "version", VERSION, 
			       "copyright", "Copyright 2002 - 2003 Jörgen Scheibengruber\nCopyright 2011 Stefano Karapetsas",
			       "comments", _("A little applet that displays some information on the traffic on the specified network device"),
			       "authors", authors, 
			       "documenters", NULL, 
			       "translator-credits", _("translator-credits"),
			       "website", "http://www.mate-desktop.org/",
			       "website-label", _("MATE Website"),
			       "logo-icon-name", LOGO_ICON,
			       NULL);
	
}

/* this basically just retrieves the new devicestring 
 * and then calls applet_device_change() and change_icons()
 */
static void
device_change_cb(GtkComboBox *combo, MateNetspeedApplet *applet)
{
	GList *devices;
	int i, active;

	g_assert(combo);
	devices = g_object_get_data(G_OBJECT(combo), "devices");
	active = gtk_combo_box_get_active(combo);
	g_assert(active > -1);

	if (0 == active) {
		if (applet->auto_change_device)
			return;
		applet->auto_change_device = TRUE;
	} else {
		applet->auto_change_device = FALSE;
		for (i = 1; i < active; i++) {
			devices = g_list_next(devices);
		}
		if (g_str_equal(devices->data, applet->devinfo.name))
			return;
		free_device_info(&applet->devinfo);
		get_device_info(devices->data, &applet->devinfo);
	}

	applet->device_has_changed = TRUE;
	update_applet(applet);
}


/* Handle preference dialog response event
 */
static void
pref_response_cb (GtkDialog *dialog, gint id, gpointer data)
{
    MateNetspeedApplet *applet = data;
  
    if(id == GTK_RESPONSE_HELP){
        display_help (GTK_WIDGET (dialog), "netspeed_applet-settings");
	return;
    }
    mate_panel_applet_mateconf_set_string(MATE_PANEL_APPLET(applet->applet), "device", applet->devinfo.name, NULL);
    mate_panel_applet_mateconf_set_bool(MATE_PANEL_APPLET(applet->applet), "show_sum", applet->show_sum, NULL);
    mate_panel_applet_mateconf_set_bool(MATE_PANEL_APPLET(applet->applet), "show_bits", applet->show_bits, NULL);
    mate_panel_applet_mateconf_set_bool(MATE_PANEL_APPLET(applet->applet), "change_icon", applet->change_icon, NULL);
    mate_panel_applet_mateconf_set_bool(MATE_PANEL_APPLET(applet->applet), "auto_change_device", applet->auto_change_device, NULL);
    mate_panel_applet_mateconf_set_bool(MATE_PANEL_APPLET(applet->applet), "have_settings", TRUE, NULL);

    gtk_widget_destroy(GTK_WIDGET(applet->settings));
    applet->settings = NULL;
}

/* Called when the showsum checkbutton is toggled...
 */
static void
showsum_change_cb(GtkToggleButton *togglebutton, MateNetspeedApplet *applet)
{
	applet->show_sum = gtk_toggle_button_get_active(togglebutton);
	applet_change_size_or_orient(applet->applet, -1, (gpointer)applet);
	change_icons(applet);
}

/* Called when the showbits checkbutton is toggled...
 */
static void
showbits_change_cb(GtkToggleButton *togglebutton, MateNetspeedApplet *applet)
{
	applet->show_bits = gtk_toggle_button_get_active(togglebutton);
}

/* Called when the changeicon checkbutton is toggled...
 */
static void
changeicon_change_cb(GtkToggleButton *togglebutton, MateNetspeedApplet *applet)
{
	applet->change_icon = gtk_toggle_button_get_active(togglebutton);
	change_icons(applet);
}

/* Creates the settings dialog
 * After its been closed, take the new values and store
 * them in the mateconf database
 */
static void
settings_cb(MateComponentUIComponent *uic, gpointer data, const gchar *verbname)
{
	MateNetspeedApplet *applet = (MateNetspeedApplet*)data;
	GtkWidget *vbox;
	GtkWidget *hbox;
	GtkWidget *categories_vbox;
	GtkWidget *category_vbox;
	GtkWidget *controls_vbox;
	GtkWidget *category_header_label;
	GtkWidget *network_device_hbox;
	GtkWidget *network_device_label;
	GtkWidget *indent_label;
	GtkWidget *show_sum_checkbutton;
	GtkWidget *show_bits_checkbutton;
	GtkWidget *change_icon_checkbutton;
	GtkSizeGroup *category_label_size_group;
	GtkSizeGroup *category_units_size_group;
  	gchar *header_str;
	GList *ptr, *devices;
	int i, active = -1;
	
	g_assert(applet);
	
	if (applet->settings)
	{
		gtk_window_present(GTK_WINDOW(applet->settings));
		return;
	}

	category_label_size_group = gtk_size_group_new(GTK_SIZE_GROUP_HORIZONTAL);
	category_units_size_group = gtk_size_group_new(GTK_SIZE_GROUP_HORIZONTAL);
  
	applet->settings = GTK_DIALOG(gtk_dialog_new_with_buttons(_("Mate Netspeed Preferences"), 
								  NULL, 
								  GTK_DIALOG_DESTROY_WITH_PARENT |
								  GTK_DIALOG_NO_SEPARATOR,	
								  GTK_STOCK_HELP, GTK_RESPONSE_HELP, 
								  GTK_STOCK_CLOSE, GTK_RESPONSE_ACCEPT, 
								  NULL));
	
	gtk_window_set_resizable(GTK_WINDOW(applet->settings), FALSE);
	gtk_window_set_screen(GTK_WINDOW(applet->settings), 
			      gtk_widget_get_screen(GTK_WIDGET(applet->settings)));
			       
	gtk_dialog_set_default_response(GTK_DIALOG(applet->settings), GTK_RESPONSE_CLOSE);

	vbox = gtk_vbox_new(FALSE, 0);
	gtk_container_set_border_width(GTK_CONTAINER(vbox), 12);

	categories_vbox = gtk_vbox_new(FALSE, 18);
	gtk_box_pack_start(GTK_BOX (vbox), categories_vbox, TRUE, TRUE, 0);

	category_vbox = gtk_vbox_new(FALSE, 6);
	gtk_box_pack_start(GTK_BOX (categories_vbox), category_vbox, TRUE, TRUE, 0);
	
	header_str = g_strconcat("<span weight=\"bold\">", _("General Settings"), "</span>", NULL);
	category_header_label = gtk_label_new(header_str);
	gtk_label_set_use_markup(GTK_LABEL(category_header_label), TRUE);
	gtk_label_set_justify(GTK_LABEL(category_header_label), GTK_JUSTIFY_LEFT);
	gtk_misc_set_alignment(GTK_MISC (category_header_label), 0, 0.5);
	gtk_box_pack_start(GTK_BOX (category_vbox), category_header_label, FALSE, FALSE, 0);
	g_free(header_str);
	
	hbox = gtk_hbox_new(FALSE, 0);
	gtk_box_pack_start(GTK_BOX (category_vbox), hbox, TRUE, TRUE, 0);

	indent_label = gtk_label_new("    ");
	gtk_label_set_justify(GTK_LABEL (indent_label), GTK_JUSTIFY_LEFT);
	gtk_box_pack_start(GTK_BOX (hbox), indent_label, FALSE, FALSE, 0);
		
	controls_vbox = gtk_vbox_new(FALSE, 10);
	gtk_box_pack_start(GTK_BOX(hbox), controls_vbox, TRUE, TRUE, 0);

	network_device_hbox = gtk_hbox_new(FALSE, 6);
	gtk_box_pack_start(GTK_BOX(controls_vbox), network_device_hbox, TRUE, TRUE, 0);
	
	network_device_label = gtk_label_new_with_mnemonic(_("Network _device:"));
	gtk_label_set_justify(GTK_LABEL(network_device_label), GTK_JUSTIFY_LEFT);
	gtk_misc_set_alignment(GTK_MISC(network_device_label), 0.0f, 0.5f);
	gtk_size_group_add_widget(category_label_size_group, network_device_label);
	gtk_box_pack_start(GTK_BOX (network_device_hbox), network_device_label, FALSE, FALSE, 0);
	
	applet->network_device_combo = gtk_combo_box_new_text();
	gtk_label_set_mnemonic_widget(GTK_LABEL(network_device_label), applet->network_device_combo);
	gtk_box_pack_start (GTK_BOX (network_device_hbox), applet->network_device_combo, TRUE, TRUE, 0);

	/* Default means device with default route set */
	gtk_combo_box_append_text(GTK_COMBO_BOX(applet->network_device_combo), _("Default"));
	ptr = devices = get_available_devices();
	for (i = 0; ptr; ptr = g_list_next(ptr)) {
		gtk_combo_box_append_text(GTK_COMBO_BOX(applet->network_device_combo), ptr->data);
		if (g_str_equal(ptr->data, applet->devinfo.name)) active = i;
		++i;
	}
	if (active < 0 || applet->auto_change_device) {
		active = 0;
	}
	gtk_combo_box_set_active(GTK_COMBO_BOX(applet->network_device_combo), active);
	g_object_set_data_full(G_OBJECT(applet->network_device_combo), "devices", devices, (GDestroyNotify)free_devices_list);

	show_sum_checkbutton = gtk_check_button_new_with_mnemonic(_("Show _sum instead of in & out"));
	gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(show_sum_checkbutton), applet->show_sum);
	gtk_box_pack_start(GTK_BOX(controls_vbox), show_sum_checkbutton, FALSE, FALSE, 0);
	
	show_bits_checkbutton = gtk_check_button_new_with_mnemonic(_("Show _bits instead of bytes"));
	gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(show_bits_checkbutton), applet->show_bits);
	gtk_box_pack_start(GTK_BOX(controls_vbox), show_bits_checkbutton, FALSE, FALSE, 0);
	
	change_icon_checkbutton = gtk_check_button_new_with_mnemonic(_("Change _icon according to the selected device"));
	gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(change_icon_checkbutton), applet->change_icon);
  	gtk_box_pack_start(GTK_BOX(controls_vbox), change_icon_checkbutton, FALSE, FALSE, 0);

	g_signal_connect(G_OBJECT (applet->network_device_combo), "changed",
			 G_CALLBACK(device_change_cb), (gpointer)applet);

	g_signal_connect(G_OBJECT (show_sum_checkbutton), "toggled",
			 G_CALLBACK(showsum_change_cb), (gpointer)applet);

	g_signal_connect(G_OBJECT (show_bits_checkbutton), "toggled",
			 G_CALLBACK(showbits_change_cb), (gpointer)applet);

	g_signal_connect(G_OBJECT (change_icon_checkbutton), "toggled",
			 G_CALLBACK(changeicon_change_cb), (gpointer)applet);

	g_signal_connect(G_OBJECT (applet->settings), "response",
			 G_CALLBACK(pref_response_cb), (gpointer)applet);

	gtk_container_add(GTK_CONTAINER(applet->settings->vbox), vbox); 

	gtk_widget_show_all(GTK_WIDGET(applet->settings));
}

static gboolean
da_expose_event(GtkWidget *widget, GdkEventExpose *event, gpointer data)
{
	MateNetspeedApplet *applet = (MateNetspeedApplet*)data;
	
	redraw_graph(applet);
	
	return FALSE;
}	

static void
incolor_changed_cb (GtkColorButton *cb, gpointer data)
{
	MateNetspeedApplet *applet = (MateNetspeedApplet*)data;
	gchar *color;
	GdkColor clr;
	
	gtk_color_button_get_color (cb, &clr);
	applet->in_color = clr;
	
	color = g_strdup_printf ("#%04x%04x%04x", clr.red, clr.green, clr.blue);
	mate_panel_applet_mateconf_set_string (MATE_PANEL_APPLET (applet->applet), "in_color", color, NULL);
	mate_panel_applet_mateconf_set_bool (MATE_PANEL_APPLET (applet->applet), "have_settings", TRUE, NULL);
	g_free (color);
}

static void
outcolor_changed_cb (GtkColorButton *cb, gpointer data)
{
	MateNetspeedApplet *applet = (MateNetspeedApplet*)data;
	gchar *color;
	GdkColor clr;
	
	gtk_color_button_get_color (cb, &clr);
	applet->out_color = clr;
	
	color = g_strdup_printf ("#%04x%04x%04x", clr.red, clr.green, clr.blue);
	mate_panel_applet_mateconf_set_string (MATE_PANEL_APPLET (applet->applet), "out_color", color, NULL);
	mate_panel_applet_mateconf_set_bool (MATE_PANEL_APPLET (applet->applet), "have_settings", TRUE, NULL);
	g_free (color);
}

/* Handle info dialog response event
 */
static void
info_response_cb (GtkDialog *dialog, gint id, MateNetspeedApplet *applet)
{
  
	if(id == GTK_RESPONSE_HELP){
		display_help (GTK_WIDGET (dialog), "mate_netspeed_applet-details");
		return;
	}
	
	gtk_widget_destroy(GTK_WIDGET(applet->details));
	
	applet->details = NULL;
	applet->inbytes_text = NULL;
	applet->outbytes_text = NULL;
	applet->drawingarea = NULL;
	applet->signalbar = NULL;
}

/* Creates the details dialog
 */
static void
showinfo_cb(MateComponentUIComponent *uic, gpointer data, const gchar *verbname)
{
	MateNetspeedApplet *applet = (MateNetspeedApplet*)data;
	GtkWidget *box, *hbox;
	GtkWidget *table, *da_frame;
	GtkWidget *ip_label, *netmask_label;
	GtkWidget *hwaddr_label, *ptpip_label;
	GtkWidget *ip_text, *netmask_text;
	GtkWidget *hwaddr_text, *ptpip_text;
	GtkWidget *inbytes_label, *outbytes_label;
	GtkWidget *incolor_sel, *incolor_label;
	GtkWidget *outcolor_sel, *outcolor_label;
	char *title;
	
	g_assert(applet);
	
	if (applet->details)
	{
		gtk_window_present(GTK_WINDOW(applet->details));
		return;
	}
	
	title = g_strdup_printf(_("Device Details for %s"), applet->devinfo.name);
	applet->details = GTK_DIALOG(gtk_dialog_new_with_buttons(title, 
		NULL, 
		GTK_DIALOG_DESTROY_WITH_PARENT |
	 	GTK_DIALOG_NO_SEPARATOR,
		GTK_STOCK_CLOSE, GTK_RESPONSE_ACCEPT, 
		GTK_STOCK_HELP, GTK_RESPONSE_HELP,
		NULL));
	g_free(title);

	gtk_dialog_set_default_response(GTK_DIALOG(applet->details), GTK_RESPONSE_CLOSE);
	
	box = gtk_vbox_new(FALSE, 10);
	gtk_container_set_border_width(GTK_CONTAINER(box), 12);
	
	table = gtk_table_new(4, 4, FALSE);
	gtk_table_set_row_spacings(GTK_TABLE(table), 10);
	gtk_table_set_col_spacings(GTK_TABLE(table), 15);
	
	da_frame = gtk_frame_new(NULL);
	gtk_frame_set_shadow_type(GTK_FRAME(da_frame), GTK_SHADOW_IN);
	applet->drawingarea = GTK_DRAWING_AREA(gtk_drawing_area_new());
	gtk_widget_set_size_request(GTK_WIDGET(applet->drawingarea), -1, 180);
	gtk_container_add(GTK_CONTAINER(da_frame), GTK_WIDGET(applet->drawingarea));
	
	hbox = gtk_hbox_new(FALSE, 5);
	incolor_label = gtk_label_new_with_mnemonic(_("_In graph color"));
	outcolor_label = gtk_label_new_with_mnemonic(_("_Out graph color"));
	
	incolor_sel = gtk_color_button_new ();
	outcolor_sel = gtk_color_button_new ();
	
	gtk_color_button_set_color (GTK_COLOR_BUTTON (incolor_sel),  &applet->in_color);
	gtk_color_button_set_color (GTK_COLOR_BUTTON (outcolor_sel),  &applet->out_color);

	gtk_label_set_mnemonic_widget(GTK_LABEL(incolor_label), incolor_sel);
	gtk_label_set_mnemonic_widget(GTK_LABEL(outcolor_label), outcolor_sel);
	
	gtk_box_pack_start(GTK_BOX(hbox), incolor_sel, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(hbox), incolor_label, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(hbox), outcolor_sel, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(hbox), outcolor_label, FALSE, FALSE, 0);
	
	ip_label = gtk_label_new(_("Internet Address:"));
	netmask_label = gtk_label_new(_("Netmask:"));
	hwaddr_label = gtk_label_new(_("Hardware Address:"));
	ptpip_label = gtk_label_new(_("P-t-P Address:"));
	inbytes_label = gtk_label_new(_("Bytes in:"));
	outbytes_label = gtk_label_new(_("Bytes out:"));
	
	ip_text = gtk_label_new(applet->devinfo.ip ? applet->devinfo.ip : _("none"));
	netmask_text = gtk_label_new(applet->devinfo.netmask ? applet->devinfo.netmask : _("none"));
	hwaddr_text = gtk_label_new(applet->devinfo.hwaddr ? applet->devinfo.hwaddr : _("none"));
	ptpip_text = gtk_label_new(applet->devinfo.ptpip ? applet->devinfo.ptpip : _("none"));
	applet->inbytes_text = gtk_label_new("0 byte");
	applet->outbytes_text = gtk_label_new("0 byte");

	gtk_label_set_selectable(GTK_LABEL(ip_text), TRUE);
	gtk_label_set_selectable(GTK_LABEL(netmask_text), TRUE);
	gtk_label_set_selectable(GTK_LABEL(hwaddr_text), TRUE);
	gtk_label_set_selectable(GTK_LABEL(ptpip_text), TRUE);
	
	gtk_misc_set_alignment(GTK_MISC(ip_label), 0.0f, 0.5f);
	gtk_misc_set_alignment(GTK_MISC(ip_text), 0.0f, 0.5f);
	gtk_misc_set_alignment(GTK_MISC(netmask_label), 0.0f, 0.5f);
	gtk_misc_set_alignment(GTK_MISC(netmask_text), 0.0f, 0.5f);
	gtk_misc_set_alignment(GTK_MISC(hwaddr_label), 0.0f, 0.5f);
	gtk_misc_set_alignment(GTK_MISC(hwaddr_text), 0.0f, 0.5f);
	gtk_misc_set_alignment(GTK_MISC(ptpip_label), 0.0f, 0.5f);
	gtk_misc_set_alignment(GTK_MISC(ptpip_text), 0.0f, 0.5f);
	gtk_misc_set_alignment(GTK_MISC(inbytes_label), 0.0f, 0.5f);
	gtk_misc_set_alignment(GTK_MISC(applet->inbytes_text), 0.0f, 0.5f);
	gtk_misc_set_alignment(GTK_MISC(outbytes_label), 0.0f, 0.5f);
	gtk_misc_set_alignment(GTK_MISC(applet->outbytes_text), 0.0f, 0.5f);
	
	gtk_table_attach_defaults(GTK_TABLE(table), ip_label, 0, 1, 0, 1);
	gtk_table_attach_defaults(GTK_TABLE(table), ip_text, 1, 2, 0, 1);
	gtk_table_attach_defaults(GTK_TABLE(table), netmask_label, 2, 3, 0, 1);
	gtk_table_attach_defaults(GTK_TABLE(table), netmask_text, 3, 4, 0, 1);
	gtk_table_attach_defaults(GTK_TABLE(table), hwaddr_label, 0, 1, 1, 2);
	gtk_table_attach_defaults(GTK_TABLE(table), hwaddr_text, 1, 2, 1, 2);
	gtk_table_attach_defaults(GTK_TABLE(table), ptpip_label, 2, 3, 1, 2);
	gtk_table_attach_defaults(GTK_TABLE(table), ptpip_text, 3, 4, 1, 2);
	gtk_table_attach_defaults(GTK_TABLE(table), inbytes_label, 0, 1, 2, 3);
	gtk_table_attach_defaults(GTK_TABLE(table), applet->inbytes_text, 1, 2, 2, 3);
	gtk_table_attach_defaults(GTK_TABLE(table), outbytes_label, 2, 3, 2, 3);
	gtk_table_attach_defaults(GTK_TABLE(table), applet->outbytes_text, 3, 4, 2, 3);
	
	/* check if we got an ipv6 address */
	if (applet->devinfo.ipv6 && (strlen (applet->devinfo.ipv6) > 2)) {
		GtkWidget *ipv6_label, *ipv6_text;

		ipv6_label = gtk_label_new (_("IPV6 Address:"));
		ipv6_text = gtk_label_new (applet->devinfo.ipv6);
		
		gtk_label_set_selectable (GTK_LABEL (ipv6_text), TRUE);
		
		gtk_misc_set_alignment (GTK_MISC (ipv6_label), 0.0f, 0.5f);
		gtk_misc_set_alignment (GTK_MISC (ipv6_text), 0.0f, 0.5f);
		
		gtk_table_attach_defaults (GTK_TABLE (table), ipv6_label, 0, 1, 3, 4);
		gtk_table_attach_defaults (GTK_TABLE (table), ipv6_text, 1, 2, 3, 4);
	}
	
	if (applet->devinfo.type == DEV_WIRELESS) {
		GtkWidget *signal_label;
		GtkWidget *essid_label;
		GtkWidget *essid_text;
		float quality;
		char *text;

		/* _maybe_ we can add the encrypted icon between the essid and the signal bar. */

		applet->signalbar = gtk_progress_bar_new ();

		quality = applet->devinfo.qual / 100.0f;
		if (quality > 1.0)
		quality = 1.0;

		text = g_strdup_printf ("%d %%", applet->devinfo.qual);
		gtk_progress_bar_set_fraction (GTK_PROGRESS_BAR (applet->signalbar), quality);
		gtk_progress_bar_set_text (GTK_PROGRESS_BAR (applet->signalbar), text);
		g_free(text);

		signal_label = gtk_label_new (_("Signal Strength:"));
		essid_label = gtk_label_new (_("ESSID:"));
		essid_text = gtk_label_new (applet->devinfo.essid);

		gtk_misc_set_alignment (GTK_MISC (signal_label), 0.0f, 0.5f);
		gtk_misc_set_alignment (GTK_MISC (essid_label), 0.0f, 0.5f);
		gtk_misc_set_alignment (GTK_MISC (essid_text), 0.0f, 0.5f);

		gtk_label_set_selectable (GTK_LABEL (essid_text), TRUE);

		gtk_table_attach_defaults (GTK_TABLE (table), signal_label, 2, 3, 4, 5);
		gtk_table_attach_defaults (GTK_TABLE (table), GTK_WIDGET (applet->signalbar), 3, 4, 4, 5);
		gtk_table_attach_defaults (GTK_TABLE (table), essid_label, 0, 3, 4, 5);
		gtk_table_attach_defaults (GTK_TABLE (table), essid_text, 1, 4, 4, 5);
	}

	g_signal_connect(G_OBJECT(applet->drawingarea), "expose_event",
			 GTK_SIGNAL_FUNC(da_expose_event),
			 (gpointer)applet);

	g_signal_connect(G_OBJECT(incolor_sel), "color_set", 
			 G_CALLBACK(incolor_changed_cb),
			 (gpointer)applet);
	
	g_signal_connect(G_OBJECT(outcolor_sel), "color_set",
			 G_CALLBACK(outcolor_changed_cb),
			 (gpointer)applet);

	g_signal_connect(G_OBJECT(applet->details), "response",
			 G_CALLBACK(info_response_cb), (gpointer)applet);

	gtk_box_pack_start(GTK_BOX(box), da_frame, TRUE, TRUE, 0);
	gtk_box_pack_start(GTK_BOX(box), hbox, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(box), table, FALSE, FALSE, 0);

	gtk_container_add(GTK_CONTAINER(applet->details->vbox), box); 
	gtk_widget_show_all(GTK_WIDGET(applet->details));
}	

static const MateComponentUIVerb
mate_netspeed_applet_menu_verbs [] = 
{
		MATECOMPONENT_UI_VERB("MateNetspeedAppletDetails", showinfo_cb),
		MATECOMPONENT_UI_VERB("MateNetspeedAppletProperties", settings_cb),
		MATECOMPONENT_UI_UNSAFE_VERB("MateNetspeedAppletHelp", help_cb),
		MATECOMPONENT_UI_VERB("MateNetspeedAppletAbout", about_cb),
	
		MATECOMPONENT_UI_VERB_END
};

/* Block the size_request signal emit by the label if the
 * text changes. Only if the label wants to grow, we give
 * permission. This will eventually result in the maximal
 * size of the applet and prevents the icons and labels from
 * "jumping around" in the mate_panel which looks uggly
 */
static void
label_size_request_cb(GtkWidget *widget, GtkRequisition *requisition, MateNetspeedApplet *applet)
{
	if (applet->labels_dont_shrink) {
		if (requisition->width <= applet->width)
			requisition->width = applet->width;
		else
			applet->width = requisition->width;
	}
}	

static gboolean
applet_button_press(GtkWidget *widget, GdkEventButton *event, MateNetspeedApplet *applet)
{
	if (event->button == 1)
	{
		GError *error = NULL;
		
		if (applet->connect_dialog) 
		{	
			gtk_window_present(GTK_WINDOW(applet->connect_dialog));
			return FALSE;
		}
		
		if (applet->up_cmd && applet->down_cmd)
		{
			char *question;
			int response;
			
			if (applet->devinfo.up) 
			{
				question = g_strdup_printf(_("Do you want to disconnect %s now?"), applet->devinfo.name); 
			} 
			else
			{
				question = g_strdup_printf(_("Do you want to connect %s now?"), applet->devinfo.name);
			}
			
			applet->connect_dialog = gtk_message_dialog_new(NULL, 
					GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
					GTK_MESSAGE_QUESTION, GTK_BUTTONS_YES_NO,
					"%s",
					question);
			response = gtk_dialog_run(GTK_DIALOG(applet->connect_dialog));
			gtk_widget_destroy (applet->connect_dialog);
			applet->connect_dialog = NULL;
			g_free(question);
			
			if (response == GTK_RESPONSE_YES)
			{
				GtkWidget *dialog;
				char *command;
				
				command = g_strdup_printf("%s %s", 
					applet->devinfo.up ? applet->down_cmd : applet->up_cmd,
					applet->devinfo.name);

				if (!g_spawn_command_line_async(command, &error))
				{
					
					dialog = gtk_message_dialog_new(NULL, 
							GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
							GTK_MESSAGE_ERROR, GTK_BUTTONS_OK,
							"%s",
							error->message);
					gtk_dialog_run (GTK_DIALOG (dialog));
					gtk_widget_destroy (dialog);
					g_error_free (error);
				}
				g_free(command);
			} 
		}	
	}
	
	return FALSE;
}	

/* Frees the applet and all the data it contains
 * Removes the timeout_cb
 */
static void
applet_destroy(MatePanelApplet *applet_widget, MateNetspeedApplet *applet)
{
	g_assert(applet);
	
	g_source_remove(applet->timeout_id);
	applet->timeout_id = 0;
	
	if (applet->up_cmd)
		g_free(applet->up_cmd);
	if (applet->down_cmd)
		g_free(applet->down_cmd);
	
	/* Should never be NULL */
	free_device_info(&applet->devinfo);
	g_free(applet);
	return;
}



static void
update_tooltip(MateNetspeedApplet* applet)
{
  GString* tooltip;

  if (!applet->show_tooltip)
    return;

  tooltip = g_string_new("");

  if (!applet->devinfo.running)
    g_string_printf(tooltip, _("%s is down"), applet->devinfo.name);
  else {
    if (applet->show_sum) {
      g_string_printf(
		      tooltip,
		      _("%s: %s\nin: %s out: %s"),
		      applet->devinfo.name,
		      applet->devinfo.ip ? applet->devinfo.ip : _("has no ip"),
		      applet->devinfo.rx_rate,
		      applet->devinfo.tx_rate
		      );
    } else {
      g_string_printf(
		      tooltip,
		      _("%s: %s\nsum: %s"),
		      applet->devinfo.name,
		      applet->devinfo.ip ? applet->devinfo.ip : _("has no ip"),
		      applet->devinfo.sum_rate
		      );
    }
    if (applet->devinfo.type == DEV_WIRELESS)
      g_string_append_printf(
			     tooltip,
			     _("\nESSID: %s\nStrength: %d %%"),
			     applet->devinfo.essid ? applet->devinfo.essid : _("unknown"),
			     applet->devinfo.qual
			     );

  }

  gtk_widget_set_tooltip_text(GTK_WIDGET(applet->applet), tooltip->str);
  gtk_widget_trigger_tooltip_query(GTK_WIDGET(applet->applet));
  g_string_free(tooltip, TRUE);
}


static gboolean
mate_netspeed_enter_cb(GtkWidget *widget, GdkEventCrossing *event, gpointer data)
{
	MateNetspeedApplet *applet = data;

	applet->show_tooltip = TRUE;
	update_tooltip(applet);

	return TRUE;
}

static gboolean
mate_netspeed_leave_cb(GtkWidget *widget, GdkEventCrossing *event, gpointer data)
{
	MateNetspeedApplet *applet = data;

	applet->show_tooltip = FALSE;
	return TRUE;
}

/* The "main" function of the applet
 */
static gboolean
mate_netspeed_applet_factory(MatePanelApplet *applet_widget, const gchar *iid, gpointer data)
{
	MateNetspeedApplet *applet;
	int i;
	char* menu_string;
	GtkIconTheme *icon_theme;
	GtkWidget *spacer, *spacer_box;
	
	if (strcmp (iid, "OAFIID:MATE_NetspeedApplet"))
		return FALSE;

	glibtop_init();
	g_set_application_name (_("Mate Netspeed"));

	icon_theme = gtk_icon_theme_get_default();
	
	/* Alloc the applet. The "NULL-setting" is really redudant
 	 * but aren't we paranoid?
	 */
	applet = g_malloc0(sizeof(MateNetspeedApplet));
	applet->applet = applet_widget;
	memset(&applet->devinfo, 0, sizeof(DevInfo));
	applet->refresh_time = 1000.0;
	applet->show_sum = FALSE;
	applet->show_bits = FALSE;
	applet->change_icon = TRUE;
	applet->auto_change_device = TRUE;

	/* Set the default colors of the graph
	*/
	applet->in_color.red = 0xdf00;
	applet->in_color.green = 0x2800;
	applet->in_color.blue = 0x4700;
	applet->out_color.red = 0x3700;
	applet->out_color.green = 0x2800;
	applet->out_color.blue = 0xdf00;
		
	for (i = 0; i < GRAPH_VALUES; i++)
	{
		applet->in_graph[i] = -1;
		applet->out_graph[i] = -1;
	}	
	
	/* Get stored settings from the mateconf database
	 */
	if (mate_panel_applet_mateconf_get_bool(MATE_PANEL_APPLET(applet->applet), "have_settings", NULL))
	{	
		char *tmp = NULL;
		
		applet->show_sum = mate_panel_applet_mateconf_get_bool(applet_widget, "show_sum", NULL);
		applet->show_bits = mate_panel_applet_mateconf_get_bool(applet_widget, "show_bits", NULL);
		applet->change_icon = mate_panel_applet_mateconf_get_bool(applet_widget, "change_icon", NULL);
		applet->auto_change_device = mate_panel_applet_mateconf_get_bool(applet_widget, "auto_change_device", NULL);
		
		tmp = mate_panel_applet_mateconf_get_string(applet_widget, "device", NULL);
		if (tmp && strcmp(tmp, "")) 
		{
			get_device_info(tmp, &applet->devinfo);
			g_free(tmp);
		}
		tmp = mate_panel_applet_mateconf_get_string(applet_widget, "up_command", NULL);
		if (tmp && strcmp(tmp, "")) 
		{
			applet->up_cmd = g_strdup(tmp);
			g_free(tmp);
		}
		tmp = mate_panel_applet_mateconf_get_string(applet_widget, "down_command", NULL);
		if (tmp && strcmp(tmp, "")) 
		{
			applet->down_cmd = g_strdup(tmp);
			g_free(tmp);
		}
		
		tmp = mate_panel_applet_mateconf_get_string(applet_widget, "in_color", NULL);
		if (tmp)
		{
			gdk_color_parse(tmp, &applet->in_color);
			g_free(tmp);
		}
		tmp = mate_panel_applet_mateconf_get_string(applet_widget, "out_color", NULL);
		if (tmp)
		{
			gdk_color_parse(tmp, &applet->out_color);
			g_free(tmp);
		}
	}
	
	if (!applet->devinfo.name) {
		GList *ptr, *devices = get_available_devices();
		ptr = devices;
		while (ptr) { 
			if (!g_str_equal(ptr->data, "lo")) {
				get_device_info(ptr->data, &applet->devinfo);
				break;
			}
			ptr = g_list_next(ptr);
		}
		free_devices_list(devices);		
	}
	if (!applet->devinfo.name)
		get_device_info("lo", &applet->devinfo);	
	applet->device_has_changed = TRUE;	
	
	applet->in_label = gtk_label_new("");
	applet->out_label = gtk_label_new("");
	applet->sum_label = gtk_label_new("");
	
	applet->in_pix = gtk_image_new();
	applet->out_pix = gtk_image_new();
	applet->dev_pix = gtk_image_new();
	applet->qual_pix = gtk_image_new();
	
	applet->pix_box = gtk_hbox_new(FALSE, 0);
	spacer = gtk_label_new("");
	gtk_box_pack_start(GTK_BOX(applet->pix_box), spacer, TRUE, TRUE, 0);
	spacer = gtk_label_new("");
	gtk_box_pack_end(GTK_BOX(applet->pix_box), spacer, TRUE, TRUE, 0);

	spacer_box = gtk_hbox_new(FALSE, 2);	
	gtk_box_pack_start(GTK_BOX(applet->pix_box), spacer_box, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(spacer_box), applet->qual_pix, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(spacer_box), applet->dev_pix, FALSE, FALSE, 0);

	init_quality_pixbufs(applet);
	
	applet_change_size_or_orient(applet_widget, -1, (gpointer)applet);
	gtk_widget_show_all(GTK_WIDGET(applet_widget));
	update_applet(applet);

	mate_panel_applet_set_flags(applet_widget, MATE_PANEL_APPLET_EXPAND_MINOR);
	
	applet->timeout_id = g_timeout_add(applet->refresh_time,
                           (GtkFunction)timeout_function,
                           (gpointer)applet);

	g_signal_connect(G_OBJECT(applet_widget), "change_size",
                           G_CALLBACK(applet_change_size_or_orient),
                           (gpointer)applet);

	g_signal_connect(G_OBJECT(icon_theme), "changed",
                           G_CALLBACK(icon_theme_changed_cb),
                           (gpointer)applet);

	g_signal_connect(G_OBJECT(applet_widget), "change_orient",
                           G_CALLBACK(applet_change_size_or_orient),
                           (gpointer)applet);

	g_signal_connect(G_OBJECT(applet_widget), "change_background",
                           G_CALLBACK(change_background_cb),
			   (gpointer)applet);
		       
	g_signal_connect(G_OBJECT(applet->in_label), "size_request",
                           G_CALLBACK(label_size_request_cb),
                           (gpointer)applet);

	g_signal_connect(G_OBJECT(applet->out_label), "size_request",
                           G_CALLBACK(label_size_request_cb),
                           (gpointer)applet);

	g_signal_connect(G_OBJECT(applet->sum_label), "size_request",
                           G_CALLBACK(label_size_request_cb),
                           (gpointer)applet);

	g_signal_connect(G_OBJECT(applet_widget), "destroy",
                           G_CALLBACK(applet_destroy),
                           (gpointer)applet);

	g_signal_connect(G_OBJECT(applet_widget), "button-press-event",
                           G_CALLBACK(applet_button_press),
                           (gpointer)applet);

	g_signal_connect(G_OBJECT(applet_widget), "leave_notify_event",
			 G_CALLBACK(mate_netspeed_leave_cb),
			 (gpointer)applet);

	g_signal_connect(G_OBJECT(applet_widget), "enter_notify_event",
			 G_CALLBACK(mate_netspeed_enter_cb),
			 (gpointer)applet);


	menu_string = g_strdup_printf(mate_netspeed_applet_menu_xml, _("Device _Details"), _("_Preferences..."), _("_Help"), _("_About..."));
	mate_panel_applet_setup_menu(applet_widget, menu_string,
                                 mate_netspeed_applet_menu_verbs,
                                 (gpointer)applet);
	g_free(menu_string);
	
	return TRUE;
}

MATE_PANEL_APPLET_MATECOMPONENT_FACTORY("OAFIID:MATE_NetspeedApplet_Factory", PANEL_TYPE_APPLET,
			PACKAGE, VERSION, (MatePanelAppletFactoryCallback)mate_netspeed_applet_factory, NULL)
