/*
 * kview - show a 24-bit X display inside one window on another X display,
 * converting pixels to whatever the target supports (8-bit gray e-ink, palette,
 * truecolor), and forward pointer/keyboard input back.
 *
 * Why: the Kindle's X server has an 8-bit screen; Chromium and GTK3 Firefox need
 * a TrueColor visual and draw nothing (black) there, and Xephyr cannot run deeper
 * than its host. So the browser runs on a private Xvfb (24-bit) and kview copies
 * damaged regions to the Kindle's screen.
 *
 *   kview -src :1 -dst :0 -title "L:A_N:application_ID:org.kbrowser_PC:N_WS:true_O:U"
 *         [-delay ms]    coalesce updates for <ms> before drawing (e-ink: fewer refreshes)
 *         [-nowm]        don't act as window manager on the source display
 *
 * By default kview is also a minimal EWMH window manager for the source display:
 * every top-level window fills the screen with no decorations, dialogs are centred,
 * and fullscreen/maximize requests are acknowledged (browsers only go fullscreen
 * when a WM confirms it).
 *
 * Exits when the source display goes away or the window is closed.
 */
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <X11/extensions/Xdamage.h>
#include <X11/extensions/Xfixes.h>
#include <X11/extensions/XTest.h>
#include <X11/extensions/XShm.h>
#include <sys/ipc.h>
#include <sys/shm.h>
#include <sys/select.h>
#include <sys/time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>

static Display *src, *dst;
static Window sroot, win;
static int W, H;
static Visual *dvis;
static int ddepth;
static GC gc;
static unsigned long lut[256];          /* gray level -> destination pixel (non-TrueColor) */
static int tc;                          /* destination is TrueColor/DirectColor */
static unsigned long rmask, gmask, bmask;
static int rshift, gshift, bshift, rbits, gbits, bbits;
static XShmSegmentInfo shminfo;
static int use_shm;

static int mask_shift(unsigned long m) { int s = 0; if (!m) return 0; while (!(m & 1)) { m >>= 1; s++; } return s; }
static int mask_bits(unsigned long m) { int b = 0; while (m) { b += m & 1; m >>= 1; } return b; }

static void setup_colors(void) {
    int screen = DefaultScreen(dst);
    Colormap cmap = DefaultColormap(dst, screen);
    int cls = dvis->class;
    if (cls == TrueColor || cls == DirectColor) {
        tc = 1;
        rmask = dvis->red_mask; gmask = dvis->green_mask; bmask = dvis->blue_mask;
        rshift = mask_shift(rmask); gshift = mask_shift(gmask); bshift = mask_shift(bmask);
        rbits = mask_bits(rmask); gbits = mask_bits(gmask); bbits = mask_bits(bmask);
        fprintf(stderr, "kview: dst TrueColor depth %d\n", ddepth);
        return;
    }
    /* StaticGray / GrayScale / PseudoColor / StaticColor: let the server pick the pixel
     * for each gray level (on static visuals XAllocColor returns the closest one). */
    int step = ddepth >= 8 ? 1 : 256 / (1 << ddepth);
    int got = 0;
    for (int g = 0; g < 256; g += step) {
        XColor c; c.red = c.green = c.blue = (unsigned short)(g * 257); c.flags = DoRed | DoGreen | DoBlue;
        if (XAllocColor(dst, cmap, &c)) got++;
        else { c.pixel = g < 128 ? BlackPixel(dst, screen) : WhitePixel(dst, screen); }
        for (int k = g; k < g + step && k < 256; k++) lut[k] = c.pixel;
    }
    fprintf(stderr, "kview: dst visual class %d depth %d, %d gray levels allocated\n", cls, ddepth, got);
}

static inline unsigned long convert(uint32_t p) {
    unsigned r = (p >> 16) & 0xff, g = (p >> 8) & 0xff, b = p & 0xff;
    if (tc) {
        return ((unsigned long)(r >> (8 - rbits)) << rshift) |
               ((unsigned long)(g >> (8 - gbits)) << gshift) |
               ((unsigned long)(b >> (8 - bbits)) << bshift);
    }
    return lut[(r * 77 + g * 150 + b * 29) >> 8];
}

static void blit(int x, int y, int w, int h) {
    if (x < 0) { w += x; x = 0; }
    if (y < 0) { h += y; y = 0; }
    if (x + w > W) w = W - x;
    if (y + h > H) h = H - y;
    if (w <= 0 || h <= 0) return;

    XImage *s;
    if (use_shm) {
        XImage *sub = XShmCreateImage(src, DefaultVisual(src, DefaultScreen(src)), 24, ZPixmap,
                                      shminfo.shmaddr, &shminfo, w, h);
        if (!sub || !XShmGetImage(src, sroot, sub, x, y, AllPlanes)) { if (sub) XDestroyImage(sub); return; }
        s = sub;
    } else {
        s = XGetImage(src, sroot, x, y, w, h, AllPlanes, ZPixmap);
        if (!s) return;
    }
    XImage *d = XCreateImage(dst, dvis, ddepth, ZPixmap, 0, NULL, w, h, 32, 0);
    d->data = malloc((size_t)d->bytes_per_line * h);
    if (d->bits_per_pixel == 8 && !tc) {
        for (int j = 0; j < h; j++) {
            uint32_t *sp = (uint32_t *)(s->data + (size_t)j * s->bytes_per_line);
            uint8_t *dp = (uint8_t *)(d->data + (size_t)j * d->bytes_per_line);
            for (int i = 0; i < w; i++) dp[i] = (uint8_t)convert(sp[i]);
        }
    } else if (d->bits_per_pixel == 32 && tc) {
        for (int j = 0; j < h; j++) {
            uint32_t *sp = (uint32_t *)(s->data + (size_t)j * s->bytes_per_line);
            uint32_t *dp = (uint32_t *)(d->data + (size_t)j * d->bytes_per_line);
            for (int i = 0; i < w; i++) dp[i] = (uint32_t)convert(sp[i]);
        }
    } else {
        for (int j = 0; j < h; j++) {
            uint32_t *sp = (uint32_t *)(s->data + (size_t)j * s->bytes_per_line);
            for (int i = 0; i < w; i++) XPutPixel(d, i, j, convert(sp[i]));
        }
    }
    XPutImage(dst, win, gc, d, 0, 0, x, y, w, h);
    XDestroyImage(d);
    if (use_shm) { s->data = NULL; XDestroyImage(s); } else XDestroyImage(s);
}

static KeyCode map_key(XKeyEvent *e) {
    KeySym ks = XLookupKeysym(e, 0);
    return ks == NoSymbol ? 0 : XKeysymToKeycode(src, ks);
}

/* 64-bit: `long` is 32 bits on the Kindle, and seconds*1000 would overflow it. */
static int64_t now_ms(void) { struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts); return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000; }

/* ------------------------------------------------------------------ WM ---- */
static int wm_on = 1, wm_busy;
static int strut_bottom;   /* space reserved at the bottom by dock windows (kbar) */
static Atom A_STATE, A_FS, A_MAXV, A_MAXH, A_ACTIVE, A_CHECK, A_SUPPORTED, A_FRAME,
            A_WMNAME, A_UTF8, A_WMSTATE, A_TYPE, A_DIALOG, A_DOCK, A_STRUT;

static int on_start_error(Display *d, XErrorEvent *e) { (void)d; if (e->error_code == BadAccess) wm_busy = 1; return 0; }
/* Windows vanish all the time; a stale id must not kill kview. */
static int on_error(Display *d, XErrorEvent *e) { (void)d; (void)e; return 0; }

static int has_type(Window w, Atom want) {
    Atom type; int fmt; unsigned long n, after; unsigned char *data = NULL; int hit = 0;
    if (XGetWindowProperty(src, w, A_TYPE, 0, 16, False, XA_ATOM, &type, &fmt, &n, &after, &data) == Success && data) {
        for (unsigned long i = 0; i < n; i++) if (((Atom *)data)[i] == want) hit = 1;
        XFree(data);
    }
    return hit;
}

static int is_dialog(Window w) {
    Window t = None;
    if (XGetTransientForHint(src, w, &t) && t != None) return 1;
    Atom type; int fmt; unsigned long n, after; unsigned char *data = NULL; int dlg = 0;
    if (XGetWindowProperty(src, w, A_TYPE, 0, 16, False, XA_ATOM, &type, &fmt, &n, &after, &data) == Success && data) {
        for (unsigned long i = 0; i < n; i++) if (((Atom *)data)[i] == A_DIALOG) dlg = 1;
        XFree(data);
    }
    return dlg;
}

static void wm_place(Window w, int reqw, int reqh) {
    int x = 0, y = 0, ww = W, hh = H - strut_bottom;
    if (has_type(w, A_DOCK)) {
        /* On-screen keyboards/panels: keep their own geometry, stay on top. */
        XRaiseWindow(src, w);
        return;
    }
    if (is_dialog(w)) {
        ww = reqw > W ? W : (reqw < 1 ? 1 : reqw);
        hh = reqh > H ? H : (reqh < 1 ? 1 : reqh);
        if (hh > H - strut_bottom) hh = H - strut_bottom;
        x = (W - ww) / 2; y = (H - strut_bottom - hh) / 2;
    }
    XMoveResizeWindow(src, w, x, y, ww, hh);
    XSetWindowBorderWidth(src, w, 0);
    long ext[4] = { 0, 0, 0, 0 };
    XChangeProperty(src, w, A_FRAME, XA_CARDINAL, 32, PropModeReplace, (unsigned char *)ext, 4);
    /* ICCCM: always tell the client its final geometry. */
    XConfigureEvent ce = { .type = ConfigureNotify, .display = src, .event = w, .window = w,
                           .x = x, .y = y, .width = ww, .height = hh, .border_width = 0,
                           .above = None, .override_redirect = False };
    XSendEvent(src, w, False, StructureNotifyMask, (XEvent *)&ce);
}

/* Recompute the bottom strut from mapped docks; re-place normal windows if it changed. */
static void wm_update_struts(void) {
    Window r, p, *kids = NULL; unsigned int nk = 0;
    int sb = 0;
    if (!XQueryTree(src, sroot, &r, &p, &kids, &nk)) return;
    for (unsigned int i = 0; i < nk; i++) {
        XWindowAttributes wa;
        if (!XGetWindowAttributes(src, kids[i], &wa) || wa.map_state != IsViewable || !has_type(kids[i], A_DOCK)) continue;
        Atom type; int fmt; unsigned long n, after; unsigned char *data = NULL;
        if (XGetWindowProperty(src, kids[i], A_STRUT, 0, 4, False, XA_CARDINAL, &type, &fmt, &n, &after, &data) == Success && data) {
            if (n == 4 && ((long *)data)[3] > sb) sb = (int)((long *)data)[3];
            XFree(data);
        }
    }
    if (sb != strut_bottom) {
        strut_bottom = sb;
        for (unsigned int i = 0; i < nk; i++) {
            XWindowAttributes wa;
            if (XGetWindowAttributes(src, kids[i], &wa) && !wa.override_redirect && wa.map_state == IsViewable &&
                !has_type(kids[i], A_DOCK) && wa.width > 1)
                wm_place(kids[i], wa.width, wa.height);
        }
    }
    if (kids) XFree(kids);
}

static void wm_focus(Window w) {
    XRaiseWindow(src, w);
    XSetInputFocus(src, w, RevertToPointerRoot, CurrentTime);
    XChangeProperty(src, sroot, A_ACTIVE, XA_WINDOW, 32, PropModeReplace, (unsigned char *)&w, 1);
}

static void wm_state_change(Window w, long action, Atom a1, Atom a2) {
    Atom type; int fmt; unsigned long n = 0, after; unsigned char *data = NULL;
    Atom cur[16]; int nc = 0;
    if (XGetWindowProperty(src, w, A_STATE, 0, 16, False, XA_ATOM, &type, &fmt, &n, &after, &data) == Success && data) {
        for (unsigned long i = 0; i < n && nc < 16; i++) cur[nc++] = ((Atom *)data)[i];
        XFree(data);
    }
    Atom req[2] = { a1, a2 };
    for (int k = 0; k < 2; k++) {
        if (req[k] == None) continue;
        int idx = -1;
        for (int i = 0; i < nc; i++) if (cur[i] == req[k]) idx = i;
        int want = action == 1 ? 1 : action == 0 ? 0 : idx < 0;   /* 0 remove, 1 add, 2 toggle */
        if (want && idx < 0 && nc < 16) cur[nc++] = req[k];
        if (!want && idx >= 0) cur[idx] = cur[--nc];
    }
    XChangeProperty(src, w, A_STATE, XA_ATOM, 32, PropModeReplace, (unsigned char *)cur, nc);
    /* Geometry never changes: normal, maximized and fullscreen all fill the screen. */
    XWindowAttributes wa;
    if (XGetWindowAttributes(src, w, &wa)) wm_place(w, wa.width, wa.height);
}

static void wm_init(void) {
    wm_busy = 0;
    XSetErrorHandler(on_start_error);
    XSelectInput(src, sroot, SubstructureRedirectMask | SubstructureNotifyMask);
    XSync(src, False);
    XSetErrorHandler(on_error);
    if (wm_busy) { fprintf(stderr, "kview: another WM owns %s, not managing windows\n", DisplayString(src)); wm_on = 0; return; }
    A_STATE = XInternAtom(src, "_NET_WM_STATE", False);
    A_FS = XInternAtom(src, "_NET_WM_STATE_FULLSCREEN", False);
    A_MAXV = XInternAtom(src, "_NET_WM_STATE_MAXIMIZED_VERT", False);
    A_MAXH = XInternAtom(src, "_NET_WM_STATE_MAXIMIZED_HORZ", False);
    A_ACTIVE = XInternAtom(src, "_NET_ACTIVE_WINDOW", False);
    A_CHECK = XInternAtom(src, "_NET_SUPPORTING_WM_CHECK", False);
    A_SUPPORTED = XInternAtom(src, "_NET_SUPPORTED", False);
    A_FRAME = XInternAtom(src, "_NET_FRAME_EXTENTS", False);
    A_WMNAME = XInternAtom(src, "_NET_WM_NAME", False);
    A_UTF8 = XInternAtom(src, "UTF8_STRING", False);
    A_WMSTATE = XInternAtom(src, "WM_STATE", False);
    A_TYPE = XInternAtom(src, "_NET_WM_WINDOW_TYPE", False);
    A_DIALOG = XInternAtom(src, "_NET_WM_WINDOW_TYPE_DIALOG", False);
    A_DOCK = XInternAtom(src, "_NET_WM_WINDOW_TYPE_DOCK", False);
    A_STRUT = XInternAtom(src, "_NET_WM_STRUT", False);
    Window check = XCreateSimpleWindow(src, sroot, -10, -10, 1, 1, 0, 0, 0);
    XChangeProperty(src, sroot, A_CHECK, XA_WINDOW, 32, PropModeReplace, (unsigned char *)&check, 1);
    XChangeProperty(src, check, A_CHECK, XA_WINDOW, 32, PropModeReplace, (unsigned char *)&check, 1);
    XChangeProperty(src, check, A_WMNAME, A_UTF8, 8, PropModeReplace, (unsigned char *)"kview", 5);
    Atom sup[] = { A_STATE, A_FS, A_MAXV, A_MAXH, A_ACTIVE, A_CHECK, A_SUPPORTED, A_FRAME, A_WMNAME, A_TYPE, A_DIALOG, A_DOCK };
    XChangeProperty(src, sroot, A_SUPPORTED, XA_ATOM, 32, PropModeReplace, (unsigned char *)sup, sizeof sup / sizeof *sup);
    /* Adopt windows that were mapped before us. */
    Window r, p, *kids = NULL; unsigned int nk = 0;
    if (XQueryTree(src, sroot, &r, &p, &kids, &nk)) {
        for (unsigned int i = 0; i < nk; i++) {
            XWindowAttributes wa;
            if (XGetWindowAttributes(src, kids[i], &wa) && !wa.override_redirect && wa.map_state == IsViewable && kids[i] != check)
                wm_place(kids[i], wa.width, wa.height);
        }
        if (kids) XFree(kids);
    }
}

/* Returns 1 if the event was a WM event. */
static int wm_event(XEvent *e) {
    if (!wm_on) return 0;
    switch (e->type) {
    case MapRequest: {
        Window w = e->xmaprequest.window;
        XWindowAttributes wa;
        if (!XGetWindowAttributes(src, w, &wa)) return 1;
        wm_place(w, wa.width, wa.height);
        long st[2] = { 1 /* NormalState */, None };
        XChangeProperty(src, w, A_WMSTATE, A_WMSTATE, 32, PropModeReplace, (unsigned char *)st, 2);
        XMapWindow(src, w);
        if (has_type(w, A_DOCK)) { XRaiseWindow(src, w); wm_update_struts(); } else wm_focus(w);
        return 1;
    }
    case ConfigureRequest: {
        XConfigureRequestEvent *c = &e->xconfigurerequest;
        if (has_type(c->window, A_DOCK)) {
            XWindowChanges wc = { .x = c->x, .y = c->y, .width = c->width, .height = c->height };
            XConfigureWindow(src, c->window, c->value_mask & (CWX | CWY | CWWidth | CWHeight), &wc);
            return 1;
        }
        if (is_dialog(c->window)) {
            int ww = (c->value_mask & CWWidth) ? c->width : 0, hh = (c->value_mask & CWHeight) ? c->height : 0;
            XWindowAttributes wa;
            if ((!ww || !hh) && XGetWindowAttributes(src, c->window, &wa)) { if (!ww) ww = wa.width; if (!hh) hh = wa.height; }
            wm_place(c->window, ww, hh);
        } else {
            wm_place(c->window, W, H);
        }
        if (c->value_mask & CWStackMode) XRaiseWindow(src, c->window);
        return 1;
    }
    case UnmapNotify: case DestroyNotify:
        wm_update_struts();
        return 0;
    case ClientMessage: {
        XClientMessageEvent *m = &e->xclient;
        if (m->message_type == A_STATE) wm_state_change(m->window, m->data.l[0], (Atom)m->data.l[1], (Atom)m->data.l[2]);
        else if (m->message_type == A_ACTIVE) wm_focus(m->window);
        return 1;
    }
    }
    return 0;
}

int main(int argc, char **argv) {
    const char *sname = ":1", *dname = ":0", *title = "kview";
    int delay = 60;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-nowm")) { wm_on = 0; continue; }
        if (i + 1 >= argc) break;
        if (!strcmp(argv[i], "-src")) sname = argv[++i];
        else if (!strcmp(argv[i], "-dst")) dname = argv[++i];
        else if (!strcmp(argv[i], "-title")) title = argv[++i];
        else if (!strcmp(argv[i], "-delay")) delay = atoi(argv[++i]);
    }
    if (!(src = XOpenDisplay(sname))) { fprintf(stderr, "kview: cannot open %s\n", sname); return 1; }
    if (!(dst = XOpenDisplay(dname))) { fprintf(stderr, "kview: cannot open %s\n", dname); return 1; }

    int ev, er, dmg_ev, dmg_er, maj, min;
    if (!XDamageQueryExtension(src, &dmg_ev, &dmg_er)) { fprintf(stderr, "kview: no DAMAGE on %s\n", sname); return 1; }
    if (!XTestQueryExtension(src, &ev, &er, &maj, &min)) { fprintf(stderr, "kview: no XTEST on %s\n", sname); return 1; }
    XFixesQueryExtension(src, &ev, &er);

    int sscr = DefaultScreen(src), dscr = DefaultScreen(dst);
    sroot = RootWindow(src, sscr);
    W = DisplayWidth(src, sscr); H = DisplayHeight(src, sscr);
    if (DefaultDepth(src, sscr) != 24) { fprintf(stderr, "kview: source must be 24-bit\n"); return 1; }
    dvis = DefaultVisual(dst, dscr);
    ddepth = DefaultDepth(dst, dscr);
    setup_colors();
    if (wm_on) wm_init();

    /* Title must be set before mapping: the Kindle WM parses it at map time. */
    XSetWindowAttributes a;
    a.background_pixel = WhitePixel(dst, dscr);
    a.event_mask = ExposureMask | ButtonPressMask | ButtonReleaseMask | PointerMotionMask |
                   KeyPressMask | KeyReleaseMask | StructureNotifyMask;
    win = XCreateWindow(dst, RootWindow(dst, dscr), 0, 0, W, H, 0, ddepth, InputOutput, dvis,
                        CWBackPixel | CWEventMask, &a);
    XStoreName(dst, win, title);
    XChangeProperty(dst, win, XInternAtom(dst, "_NET_WM_NAME", False), XInternAtom(dst, "UTF8_STRING", False),
                    8, PropModeReplace, (unsigned char *)title, strlen(title));
    XClassHint ch = { "kview", "KView" };
    XSetClassHint(dst, win, &ch);
    Atom wm_delete = XInternAtom(dst, "WM_DELETE_WINDOW", False);
    XSetWMProtocols(dst, win, &wm_delete, 1);
    gc = XCreateGC(dst, win, 0, NULL);
    XMapWindow(dst, win);

    use_shm = XShmQueryExtension(src);
    if (use_shm) {
        shminfo.shmid = shmget(IPC_PRIVATE, (size_t)W * H * 4, IPC_CREAT | 0600);
        shminfo.shmaddr = shminfo.shmid >= 0 ? shmat(shminfo.shmid, NULL, 0) : (char *)-1;
        shminfo.readOnly = False;
        if (shminfo.shmid < 0 || shminfo.shmaddr == (char *)-1 || !XShmAttach(src, &shminfo)) use_shm = 0;
        else { XSync(src, False); shmctl(shminfo.shmid, IPC_RMID, NULL); }
    }
    fprintf(stderr, "kview: %s %dx%d -> %s (shm %s)\n", sname, W, H, dname, use_shm ? "on" : "off");

    Damage damage = XDamageCreate(src, sroot, XDamageReportNonEmpty);
    XserverRegion region = XFixesCreateRegion(src, NULL, 0);
    int dirty = 1;              /* full redraw pending */
    int64_t first_damage = now_ms();
    int win_w = W, win_h = H;
    double sx = 1.0, sy = 1.0;  /* dst window -> src coordinates */

    int sfd = ConnectionNumber(src), dfd = ConnectionNumber(dst);
    for (;;) {
        /* source events: damage */
        while (XPending(src)) {
            XEvent e; XNextEvent(src, &e);
            if (wm_event(&e)) continue;
            if (e.type == dmg_ev + XDamageNotify) {
                if (!dirty) first_damage = now_ms();
                dirty = dirty ? dirty : 2;   /* 2 = partial */
            }
        }
        /* destination events: input, expose, resize */
        while (XPending(dst)) {
            XEvent e; XNextEvent(dst, &e);
            switch (e.type) {
            case Expose: if (!dirty) first_damage = 0; dirty = 1; break;
            case ConfigureNotify:
                win_w = e.xconfigure.width; win_h = e.xconfigure.height;
                sx = (double)W / win_w; sy = (double)H / win_h;
                break;
            case MotionNotify:
                XTestFakeMotionEvent(src, sscr, (int)(e.xmotion.x * sx), (int)(e.xmotion.y * sy), CurrentTime);
                break;
            case ButtonPress: case ButtonRelease:
                XTestFakeMotionEvent(src, sscr, (int)(e.xbutton.x * sx), (int)(e.xbutton.y * sy), CurrentTime);
                XTestFakeButtonEvent(src, e.xbutton.button, e.type == ButtonPress, CurrentTime);
                break;
            case KeyPress: case KeyRelease: {
                KeyCode kc = map_key(&e.xkey);
                if (kc) XTestFakeKeyEvent(src, kc, e.type == KeyPress, CurrentTime);
                break;
            }
            case ClientMessage:
                if ((Atom)e.xclient.data.l[0] == wm_delete) return 0;
                break;
            }
            XFlush(src);
        }
        if (dirty && now_ms() - first_damage >= delay) {
            if (dirty == 1) {
                XDamageSubtract(src, damage, None, None);
                for (int y = 0; y < H; y += 256) blit(0, y, W, H - y < 256 ? H - y : 256);
            } else {
                XDamageSubtract(src, damage, None, region);
                int n = 0;
                XRectangle *r = XFixesFetchRegion(src, region, &n);
                /* Many small rects: one bounding box is cheaper than many round trips. */
                if (n > 16) {
                    int x0 = W, y0 = H, x1 = 0, y1 = 0;
                    for (int i = 0; i < n; i++) {
                        if (r[i].x < x0) x0 = r[i].x;
                        if (r[i].y < y0) y0 = r[i].y;
                        if (r[i].x + r[i].width > x1) x1 = r[i].x + r[i].width;
                        if (r[i].y + r[i].height > y1) y1 = r[i].y + r[i].height;
                    }
                    blit(x0, y0, x1 - x0, y1 - y0);
                } else {
                    for (int i = 0; i < n; i++) blit(r[i].x, r[i].y, r[i].width, r[i].height);
                }
                if (r) XFree(r);
            }
            dirty = 0;
            XFlush(dst);
        }
        fd_set fds; FD_ZERO(&fds); FD_SET(sfd, &fds); FD_SET(dfd, &fds);
        struct timeval tv = { 0, dirty ? 20000 : 500000 };
        /* A dead source or target display makes Xlib exit the process. */
        if (select((sfd > dfd ? sfd : dfd) + 1, &fds, NULL, NULL, &tv) < 0) break;
        XEventsQueued(src, QueuedAfterReading);
        XEventsQueued(dst, QueuedAfterReading);
    }
    return 0;
}
