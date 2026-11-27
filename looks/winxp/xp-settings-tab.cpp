// kali-looks: Display Properties' Settings tab, as in Windows XP -- drag the monitor
// icons to arrange the screens, a Less/More slider for the screen resolution, the
// primary and "extend my desktop" checkboxes, Identify, and Advanced (KDE's own display
// settings, for refresh rate, rotation and scale). Read and applied with kscreen-doctor.
// (patch-xplasma.py puts this into displayproperties.cpp, before the dialog.)
#include <QMouseEvent>
#include <QPainter>
#include <QPainterPath>
#include <QProcess>
#include <QScreen>
#include <QSlider>
#include <algorithm>
#include <functional>
#include <climits>

struct XpOutput {
    struct Mode { QString id; QSize size; double refresh = 0; };
    QString name;
    int type = 0;
    bool enabled = true;
    bool primary = false;
    QPoint pos;
    QString modeId;
    int rotation = 1;
    QList<Mode> modes;
    const Mode *mode() const
    {
        for (const Mode &m : modes)
            if (m.id == modeId)
                return &m;
        return nullptr;
    }
    QSize size() const
    {
        const Mode *m = mode();
        QSize s = m ? m->size : QSize(1024, 768);
        return (rotation == 2 || rotation == 8) ? s.transposed() : s;
    }
    QRect rect() const { return QRect(pos, size()); }
    bool sameAs(const XpOutput &o) const
    {
        return enabled == o.enabled && primary == o.primary && pos == o.pos && modeId == o.modeId;
    }
    // The resolutions on offer, smallest first.
    QList<QSize> sizes() const
    {
        QList<QSize> list;
        for (const Mode &m : modes)
            if (!list.contains(m.size))
                list.append(m.size);
        std::sort(list.begin(), list.end(), [](QSize a, QSize b) {
            return a.width() * a.height() != b.width() * b.height() ? a.width() * a.height() < b.width() * b.height() : a.width() < b.width();
        });
        return list;
    }
    // This resolution's mode, at the refresh rate closest to the current one.
    QString modeFor(QSize s) const
    {
        const double now = mode() ? mode()->refresh : 60;
        QString best;
        double gap = 1e9;
        for (const Mode &m : modes)
            if (m.size == s && qAbs(m.refresh - now) < gap) {
                gap = qAbs(m.refresh - now);
                best = m.id;
            }
        return best;
    }
};

static QList<XpOutput> xpReadOutputs()
{
    QProcess p;
    p.start(QStringLiteral("kscreen-doctor"), {QStringLiteral("-j")});
    p.waitForFinished(10000);
    QList<XpOutput> list;
    const QJsonArray outputs = QJsonDocument::fromJson(p.readAllStandardOutput()).object().value(QStringLiteral("outputs")).toArray();
    for (const QJsonValue &v : outputs) {
        const QJsonObject o = v.toObject();
        if (!o.value(QStringLiteral("connected")).toBool())
            continue;
        XpOutput x;
        x.name = o.value(QStringLiteral("name")).toString();
        x.type = o.value(QStringLiteral("type")).toInt();
        x.enabled = o.value(QStringLiteral("enabled")).toBool();
        x.primary = o.value(QStringLiteral("priority")).toInt() == 1;
        const QJsonObject pos = o.value(QStringLiteral("pos")).toObject();
        x.pos = QPoint(pos.value(QStringLiteral("x")).toInt(), pos.value(QStringLiteral("y")).toInt());
        x.modeId = o.value(QStringLiteral("currentModeId")).toString();
        x.rotation = o.value(QStringLiteral("rotation")).toInt(1);
        for (const QJsonValue &mv : o.value(QStringLiteral("modes")).toArray()) {
            const QJsonObject m = mv.toObject();
            const QJsonObject s = m.value(QStringLiteral("size")).toObject();
            x.modes.append({m.value(QStringLiteral("id")).toString(),
                            QSize(s.value(QStringLiteral("width")).toInt(), s.value(QStringLiteral("height")).toInt()),
                            m.value(QStringLiteral("refreshRate")).toDouble()});
        }
        if (!x.mode() && !x.modes.isEmpty())
            x.modeId = x.modes.first().id;
        list.append(x);
    }
    // Screens that are off go to the right of the desktop, where they'd join it.
    int right = 0;
    for (const XpOutput &o : list)
        if (o.enabled)
            right = qMax(right, o.rect().right() + 1);
    for (XpOutput &o : list)
        if (!o.enabled) {
            o.pos = QPoint(right, 0);
            right += o.size().width();
        }
    return list;
}

// Where a screen dropped at r goes: against one of the others' edges, not over any of
// them, as close as can be to where it was dropped.
static bool xpSnap(const QList<QRect> &others, QRect &r)
{
    if (others.isEmpty()) {
        r.moveTopLeft(QPoint(0, 0));
        return true;
    }
    auto clampTo = [](int v, int lo, int hi) { return qMax(lo, qMin(v, hi)); };
    QList<QPoint> candidates;
    for (const QRect &o : others) {
        int y = clampTo(r.y(), o.y() - r.height() + 1, o.y() + o.height() - 1);
        if (qAbs(y - o.y()) < r.height() / 4)
            y = o.y();
        int x = clampTo(r.x(), o.x() - r.width() + 1, o.x() + o.width() - 1);
        if (qAbs(x - o.x()) < r.width() / 4)
            x = o.x();
        candidates << QPoint(o.x() - r.width(), y) << QPoint(o.x() + o.width(), y)
                   << QPoint(x, o.y() - r.height()) << QPoint(x, o.y() + o.height());
    }
    bool found = false;
    QPoint best;
    long bestGap = 0;
    for (const QPoint &c : candidates) {
        const QRect t(c, r.size());
        if (std::any_of(others.begin(), others.end(), [&](const QRect &o) { return o.intersects(t); }))
            continue;
        const long gap = qAbs(c.x() - r.x()) + qAbs(c.y() - r.y());
        if (!found || gap < bestGap) {
            found = true;
            best = c;
            bestGap = gap;
        }
    }
    if (found)
        r.moveTopLeft(best);
    return found;
}

// The monitor icons.
class XpMonitorArea : public QWidget
{
public:
    QList<XpOutput> *outs = nullptr;
    int selected = 0;
    std::function<void(int)> onSelect;
    std::function<void()> onMoved;

    XpMonitorArea()
    {
        setMinimumSize(380, 160);
        setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Fixed);
        setFocusPolicy(Qt::StrongFocus);
    }

protected:
    QRect bounds() const
    {
        QRect b;
        for (const XpOutput &o : *outs)
            b = b.united(o.rect());
        return b;
    }
    void mapping(double &scale, QPointF &shift) const
    {
        const QRect b = m_dragging ? m_bounds : bounds();
        const double w = width() - 24, h = height() - 24;
        scale = qMin(w / qMax(1, b.width()), h / qMax(1, b.height()));
        shift = QPointF((width() - b.width() * scale) / 2 - b.x() * scale, (height() - b.height() * scale) / 2 - b.y() * scale);
    }
    QRectF onScreen(const QRect &r) const
    {
        double scale;
        QPointF shift;
        mapping(scale, shift);
        return QRectF(r.x() * scale + shift.x(), r.y() * scale + shift.y(), r.width() * scale, r.height() * scale);
    }
    void paintEvent(QPaintEvent *) override
    {
        QPainter p(this);
        p.setRenderHint(QPainter::Antialiasing, false);
        p.fillRect(rect(), palette().base());
        p.setPen(palette().mid().color());
        p.drawRect(rect().adjusted(0, 0, -1, -1));
        if (!outs)
            return;
        // the selected screen last, on top
        QList<int> order;
        for (int i = 0; i < outs->size(); ++i)
            if (i != selected)
                order << i;
        order << selected;
        for (int i : order) {
            const XpOutput &o = (*outs)[i];
            QRectF r = onScreen(o.rect()).adjusted(1, 1, -1, -1);
            if (m_dragging && i == selected)
                r.translate(m_dragOffset);
            const bool on = o.enabled;
            p.setPen(QPen(QColor(0, 0, 0), 1));
            p.setBrush(on ? QColor(0x3a, 0x6e, 0xa5) : QColor(0xa0, 0xa0, 0xa0));
            p.drawRect(r);
            p.setPen(QPen(QColor(255, 255, 255), 1));
            p.drawLine(r.topLeft() + QPointF(1, 1), r.topRight() + QPointF(-1, 1));
            p.drawLine(r.topLeft() + QPointF(1, 1), r.bottomLeft() + QPointF(1, -1));
            if (i == selected) {
                p.setBrush(Qt::NoBrush);
                p.setPen(QPen(QColor(0, 0, 0), 1, Qt::DotLine));
                p.drawRect(r.adjusted(-3, -3, 3, 3));
            }
            QFont f(QStringLiteral("Arial"));
            f.setBold(true);
            f.setPixelSize(int(qMax(14.0, qMin(r.height() * 0.55, 48.0))));
            p.setFont(f);
            p.setPen(on ? QColor(255, 255, 255) : QColor(0x60, 0x60, 0x60));
            p.drawText(r, Qt::AlignCenter, QString::number(i + 1));
        }
    }
    int hit(const QPoint &pt) const
    {
        if (outs && selected < outs->size() && onScreen((*outs)[selected].rect()).contains(pt))
            return selected;
        for (int i = outs ? outs->size() - 1 : -1; i >= 0; --i)
            if (onScreen((*outs)[i].rect()).contains(pt))
                return i;
        return -1;
    }
    void mousePressEvent(QMouseEvent *e) override
    {
        const int i = hit(e->position().toPoint());
        if (i < 0)
            return;
        selected = i;
        if (onSelect)
            onSelect(i);
        m_pressed = true;
        m_dragging = false;
        m_bounds = bounds();
        m_pressAt = e->position();
        m_dragOffset = QPointF();
        update();
    }
    void mouseMoveEvent(QMouseEvent *e) override
    {
        if (!m_pressed || outs->size() < 2)
            return;
        if (!m_dragging && (e->position() - m_pressAt).manhattanLength() < 4)
            return;
        m_dragging = true;
        m_dragOffset = e->position() - m_pressAt;
        update();
    }
    void mouseReleaseEvent(QMouseEvent *) override
    {
        if (m_dragging) {
            double scale;
            QPointF shift;
            mapping(scale, shift);
            XpOutput &o = (*outs)[selected];
            QRect r = o.rect();
            r.translate(int(m_dragOffset.x() / scale), int(m_dragOffset.y() / scale));
            QList<QRect> others;
            for (int i = 0; i < outs->size(); ++i)
                if (i != selected && (*outs)[i].enabled)
                    others << (*outs)[i].rect();
            if (xpSnap(others, r)) {
                o.pos = r.topLeft();
                if (onMoved)
                    onMoved();
            }
        }
        m_pressed = m_dragging = false;
        m_dragOffset = QPointF();
        update();
    }

private:
    bool m_pressed = false, m_dragging = false;
    QPointF m_pressAt, m_dragOffset;
    QRect m_bounds;
};

class XpSettingsTab : public QWidget
{
public:
    std::function<void()> changed;

    XpSettingsTab()
    {
        auto *v = new QVBoxLayout(this);
        v->addWidget(new QLabel(QStringLiteral("Drag the monitor icons to match the physical arrangement of your monitors.")));
        m_area = new XpMonitorArea;
        m_area->outs = &m_outs;
        v->addWidget(m_area);
        auto *displayLabel = new QLabel(QStringLiteral("&Display:"));
        m_display = new QComboBox;
        displayLabel->setBuddy(m_display);
        v->addWidget(displayLabel);
        v->addWidget(m_display);

        auto *groups = new QHBoxLayout;
        auto *resBox = new QGroupBox(QStringLiteral("Screen &resolution"));
        auto *resGrid = new QGridLayout(resBox);
        m_res = new QSlider(Qt::Horizontal);
        m_res->setTickPosition(QSlider::TicksBelow);
        m_res->setPageStep(1);
        resGrid->addWidget(new QLabel(QStringLiteral("Less")), 0, 0);
        resGrid->addWidget(m_res, 0, 1);
        resGrid->addWidget(new QLabel(QStringLiteral("More")), 0, 2);
        m_resLabel = new QLabel;
        m_resLabel->setAlignment(Qt::AlignCenter);
        resGrid->addWidget(m_resLabel, 1, 0, 1, 3);
        groups->addWidget(resBox, 1);
        auto *colorBox = new QGroupBox(QStringLiteral("&Color quality"));
        auto *colorLayout = new QVBoxLayout(colorBox);
        auto *color = new QComboBox;
        color->addItem(QStringLiteral("Highest (32 bit)"));
        colorLayout->addWidget(color);
        auto *bar = new QLabel;
        QPixmap strip(160, 10);
        {
            QPainter sp(&strip);
            QLinearGradient g(0, 0, 160, 0);
            const QList<QColor> stops = {Qt::red, Qt::yellow, Qt::green, Qt::cyan, Qt::blue, Qt::magenta, Qt::red};
            for (int i = 0; i < stops.size(); ++i)
                g.setColorAt(double(i) / (stops.size() - 1), stops[i]);
            sp.fillRect(strip.rect(), g);
            sp.setPen(Qt::black);
            sp.drawRect(strip.rect().adjusted(0, 0, -1, -1));
        }
        bar->setPixmap(strip);
        colorLayout->addWidget(bar);
        groups->addWidget(colorBox, 1);
        v->addLayout(groups);

        m_primary = new QCheckBox(QStringLiteral("Use this device as the primary monitor."));
        m_extend = new QCheckBox(QStringLiteral("Extend my Windows desktop onto this monitor."));
        v->addWidget(m_primary);
        v->addWidget(m_extend);

        auto *buttons = new QHBoxLayout;
        buttons->addStretch(1);
        auto *identify = new QPushButton(QStringLiteral("&Identify"));
        auto *advanced = new QPushButton(QStringLiteral("Ad&vanced"));
        advanced->setToolTip(QStringLiteral("Refresh rate, rotation and scale (KDE's display settings)"));
        buttons->addWidget(identify);
        buttons->addWidget(advanced);
        v->addLayout(buttons);
        v->addStretch(1);

        connect(identify, &QPushButton::clicked, this, [this] { identifyScreens(); });
        connect(advanced, &QPushButton::clicked, this, [] {
            QProcess::startDetached(QStringLiteral("kcmshell6"), {QStringLiteral("kcm_kscreen")});
        });
        m_area->onSelect = [this](int i) { select(i); };
        m_area->onMoved = [this] { normalize(); emitChanged(); };
        connect(m_display, &QComboBox::currentIndexChanged, this, [this](int i) {
            if (!m_loading && i >= 0)
                select(i);
        });
        connect(m_res, &QSlider::valueChanged, this, [this](int value) {
            if (!m_loading)
                resolutionPicked(value);
        });
        connect(m_primary, &QCheckBox::toggled, this, [this](bool on) {
            if (m_loading || !on)
                return;
            for (int i = 0; i < m_outs.size(); ++i)
                m_outs[i].primary = i == m_area->selected;
            select(m_area->selected);
            emitChanged();
        });
        connect(m_extend, &QCheckBox::toggled, this, [this](bool on) {
            if (m_loading)
                return;
            XpOutput &o = m_outs[m_area->selected];
            o.enabled = on;
            if (on) {
                QRect r = o.rect();
                QList<QRect> others;
                int right = 0;
                for (int i = 0; i < m_outs.size(); ++i)
                    if (i != m_area->selected && m_outs[i].enabled) {
                        others << m_outs[i].rect();
                        right = qMax(right, m_outs[i].rect().right() + 1);
                    }
                r.moveTopLeft(QPoint(right, 0));
                xpSnap(others, r);
                o.pos = r.topLeft();
            }
            normalize();
            select(m_area->selected);
            emitChanged();
        });
        reload();
    }

    bool pending() const
    {
        if (m_outs.size() != m_applied.size())
            return false;
        for (int i = 0; i < m_outs.size(); ++i)
            if (!m_outs[i].sameAs(m_applied[i]))
                return true;
        return false;
    }

    bool apply()
    {
        if (!pending())
            return true;
        bool resized = false;
        for (int i = 0; i < m_outs.size(); ++i)
            resized = resized || m_outs[i].modeId != m_applied[i].modeId || m_outs[i].enabled != m_applied[i].enabled;
        QString error;
        if (!run(m_outs, m_applied, &error)) {
            QMessageBox::warning(this, QStringLiteral("Display Properties"), error);
            reload();
            return false;
        }
        if (resized && !confirm()) {
            run(m_applied, m_outs, &error);
            reload();
            return true;
        }
        reload();
        return true;
    }

private:
    QList<XpOutput> m_outs, m_applied;
    XpMonitorArea *m_area;
    QComboBox *m_display;
    QSlider *m_res;
    QLabel *m_resLabel;
    QCheckBox *m_primary, *m_extend;
    bool m_loading = false;

    void emitChanged()
    {
        m_area->update();
        if (changed)
            changed();
    }

    void reload()
    {
        const int was = m_area->selected;
        m_outs = xpReadOutputs();
        m_applied = m_outs;
        m_loading = true;
        m_display->clear();
        for (int i = 0; i < m_outs.size(); ++i) {
            const XpOutput &o = m_outs[i];
            const QString kind = o.type == 7 || o.type == 8 ? QStringLiteral("Built-in Display") : QStringLiteral("Plug and Play Monitor");
            m_display->addItem(QStringLiteral("%1. %2 on %3").arg(i + 1).arg(kind, o.name));
        }
        m_loading = false;
        int start = was < m_outs.size() ? was : 0;
        if (was >= m_outs.size())
            for (int i = 0; i < m_outs.size(); ++i)
                if (m_outs[i].primary)
                    start = i;
        if (!m_outs.isEmpty())
            select(start);
        setEnabled(!m_outs.isEmpty());
        emitChanged();
    }

    void select(int i)
    {
        if (i < 0 || i >= m_outs.size())
            return;
        m_loading = true;
        m_area->selected = i;
        m_display->setCurrentIndex(i);
        const XpOutput &o = m_outs[i];
        const QList<QSize> sizes = o.sizes();
        m_res->setRange(0, qMax(0, int(sizes.size()) - 1));
        const QSize now = o.mode() ? o.mode()->size : QSize();
        m_res->setValue(qMax(0, int(sizes.indexOf(now))));
        m_res->setEnabled(o.enabled && sizes.size() > 1);
        m_resLabel->setText(QStringLiteral("%1 by %2 pixels").arg(now.width()).arg(now.height()));
        m_primary->setChecked(o.primary);
        m_primary->setEnabled(o.enabled && !o.primary);
        m_extend->setChecked(o.enabled);
        int on = 0;
        for (const XpOutput &x : m_outs)
            on += x.enabled;
        m_extend->setEnabled(!o.primary && (!o.enabled || on > 1));
        m_loading = false;
        m_area->update();
    }

    void resolutionPicked(int value)
    {
        XpOutput &o = m_outs[m_area->selected];
        const QList<QSize> sizes = o.sizes();
        if (value < 0 || value >= sizes.size())
            return;
        const QRect before = o.rect();
        const QString id = o.modeFor(sizes[value]);
        if (id.isEmpty() || id == o.modeId)
            return;
        o.modeId = id;
        // Screens beside or below it move with its new edge.
        const int dx = o.rect().width() - before.width(), dy = o.rect().height() - before.height();
        for (int i = 0; i < m_outs.size(); ++i) {
            if (i == m_area->selected || !m_outs[i].enabled)
                continue;
            if (m_outs[i].pos.x() >= before.x() + before.width())
                m_outs[i].pos.rx() += dx;
            if (m_outs[i].pos.y() >= before.y() + before.height())
                m_outs[i].pos.ry() += dy;
        }
        normalize();
        m_resLabel->setText(QStringLiteral("%1 by %2 pixels").arg(sizes[value].width()).arg(sizes[value].height()));
        emitChanged();
    }

    // The desktop starts at 0,0.
    void normalize()
    {
        int x = INT_MAX, y = INT_MAX;
        for (const XpOutput &o : m_outs)
            if (o.enabled) {
                x = qMin(x, o.pos.x());
                y = qMin(y, o.pos.y());
            }
        if (x == INT_MAX)
            return;
        for (XpOutput &o : m_outs)
            o.pos -= QPoint(x, y);
    }

    static bool run(const QList<XpOutput> &want, const QList<XpOutput> &have, QString *error)
    {
        QStringList args;
        bool primaryMoved = false;
        for (int i = 0; i < want.size(); ++i)
            primaryMoved = primaryMoved || want[i].primary != have[i].primary || want[i].enabled != have[i].enabled;
        int priority = 2;
        for (int i = 0; i < want.size(); ++i) {
            const XpOutput &w = want[i], &h = have[i];
            if (w.enabled != h.enabled)
                args << QStringLiteral("output.%1.%2").arg(w.name, w.enabled ? QStringLiteral("enable") : QStringLiteral("disable"));
            if (!w.enabled)
                continue;
            if (w.modeId != h.modeId)
                args << QStringLiteral("output.%1.mode.%2").arg(w.name, w.modeId);
            if (w.pos != h.pos || w.enabled != h.enabled)
                args << QStringLiteral("output.%1.position.%2,%3").arg(w.name).arg(w.pos.x()).arg(w.pos.y());
            if (primaryMoved)
                args << QStringLiteral("output.%1.priority.%2").arg(w.name).arg(w.primary ? 1 : priority++);
        }
        if (args.isEmpty())
            return true;
        QProcess p;
        p.start(QStringLiteral("kscreen-doctor"), args);
        if (!p.waitForFinished(20000) || p.exitStatus() != QProcess::NormalExit || p.exitCode() != 0) {
            *error = QStringLiteral("Windows could not change the display settings.\n\n") + QString::fromLocal8Bit(p.readAllStandardError()).trimmed();
            return false;
        }
        return true;
    }

    // XP's "Monitor Settings" question: keep the new resolution, or go back on its own
    // after 15 seconds (in case the screen can't show it).
    bool confirm()
    {
        QMessageBox box(QMessageBox::Question, QStringLiteral("Monitor Settings"),
                        QStringLiteral("Your desktop has been reconfigured. Do you want to keep these settings?"),
                        QMessageBox::Yes | QMessageBox::No, this);
        box.setDefaultButton(QMessageBox::No);
        int left = 15;
        auto text = [&] { box.setInformativeText(QStringLiteral("Reverting in %1 seconds.").arg(left)); };
        text();
        QTimer tick;
        QObject::connect(&tick, &QTimer::timeout, &box, [&] {
            if (--left <= 0)
                box.done(QMessageBox::No);
            else
                text();
        });
        tick.start(1000);
        return box.exec() == QMessageBox::Yes;
    }

    // Each screen's number, big, on that screen for a moment.
    void identifyScreens()
    {
        for (int i = 0; i < m_outs.size(); ++i) {
            if (!m_outs[i].enabled)
                continue;
            QScreen *screen = nullptr;
            for (QScreen *s : QGuiApplication::screens())
                if (s->name() == m_outs[i].name)
                    screen = s;
            if (!screen)
                continue;
            auto *w = new QWidget(nullptr, Qt::ToolTip | Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint);
            w->setAttribute(Qt::WA_TranslucentBackground);
            w->setAttribute(Qt::WA_DeleteOnClose);
            w->setAttribute(Qt::WA_ShowWithoutActivating);
            const QString number = QString::number(i + 1);
            const QSize size(220, 260);
            w->setFixedSize(size);
            w->move(screen->geometry().topLeft() + QPoint(60, 60));
            struct Painter : QObject {
                QString number;
                bool eventFilter(QObject *o, QEvent *e) override
                {
                    if (e->type() != QEvent::Paint)
                        return false;
                    auto *w = static_cast<QWidget *>(o);
                    QPainter p(w);
                    p.setRenderHint(QPainter::Antialiasing);
                    QFont f(QStringLiteral("Arial"));
                    f.setBold(true);
                    f.setPixelSize(220);
                    QPainterPath path;
                    path.addText(10, 220, f, number);
                    p.setPen(QPen(Qt::black, 6));
                    p.setBrush(Qt::white);
                    p.drawPath(path);
                    return true;
                }
            };
            auto *painter = new Painter;
            painter->number = number;
            painter->setParent(w);
            w->installEventFilter(painter);
            w->show();
            QTimer::singleShot(2500, w, &QWidget::close);
        }
    }
};

