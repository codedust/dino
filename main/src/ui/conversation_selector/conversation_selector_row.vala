using Gee;
using Gdk;
using Gtk;
using Pango;

using Dino;
using Dino.Entities;
using Xmpp;

namespace Dino.Ui {

[GtkTemplate (ui = "/im/dino/Dino/conversation_selector/conversation_row.ui")]
public class ConversationSelectorRow : ListBoxRow {

    [GtkChild] protected AvatarImage image;
    [GtkChild] protected Label name_label;
    [GtkChild] protected Label time_label;
    [GtkChild] protected Label nick_label;
    [GtkChild] protected Label message_label;
    [GtkChild] protected Label unread_count_label;
    [GtkChild] protected Button x_button;
    [GtkChild] protected Revealer time_revealer;
    [GtkChild] protected Revealer xbutton_revealer;
    [GtkChild] public Revealer main_revealer;

    public Conversation conversation { get; private set; }

    protected const int AVATAR_SIZE = 40;

    protected ContentItem? last_content_item;
    protected int num_unread = 0;


    protected StreamInteractor stream_interactor;

    construct {
        name_label.attributes = new AttrList();
    }

    public ConversationSelectorRow(StreamInteractor stream_interactor, Conversation conversation) {
        this.conversation = conversation;
        this.stream_interactor = stream_interactor;

        switch (conversation.type_) {
            case Conversation.Type.CHAT:
                stream_interactor.get_module(RosterManager.IDENTITY).updated_roster_item.connect((account, jid, roster_item) => {
                    if (conversation.account.equals(account) && conversation.counterpart.equals(jid)) {
                        update_name_label();
                    }
                });
                break;
            case Conversation.Type.GROUPCHAT:
                stream_interactor.get_module(MucManager.IDENTITY).room_name_set.connect((account, jid, room_name) => {
                    if (conversation != null && conversation.counterpart.equals_bare(jid) && conversation.account.equals(account)) {
                        update_name_label();
                    }
                });
                stream_interactor.get_module(MucManager.IDENTITY).private_room_occupant_updated.connect((account, room, occupant) => {
                    if (conversation != null && conversation.counterpart.equals_bare(room.bare_jid) && conversation.account.equals(account)) {
                        update_name_label();
                    }
                });
                break;
            case Conversation.Type.GROUPCHAT_PM:
                break;
        }

        // Set tooltip
        switch (conversation.type_) {
            case Conversation.Type.CHAT:
                has_tooltip = true;
                query_tooltip.connect ((x, y, keyboard_tooltip, tooltip) => {
                    tooltip.set_custom(generate_tooltip());
                    return true;
                });
                break;
            case Conversation.Type.GROUPCHAT:
                has_tooltip = true;
                set_tooltip_text(conversation.counterpart.bare_jid.to_string());
                break;
            case Conversation.Type.GROUPCHAT_PM:
                break;
        }

        stream_interactor.get_module(ContentItemStore.IDENTITY).new_item.connect((item, c) => {
            if (conversation.equals(c)) {
                content_item_received(item);
            }
        });
        last_content_item = stream_interactor.get_module(ContentItemStore.IDENTITY).get_latest(conversation);

        x_button.clicked.connect(() => {
            stream_interactor.get_module(ConversationManager.IDENTITY).close_conversation(conversation);
        });
        image.set_conversation(stream_interactor, conversation);
        conversation.notify["read-up-to"].connect(update_read);

        update_name_label();
        content_item_received();
    }

    public void update() {
        update_time_label();
    }

    public void content_item_received(ContentItem? ci = null) {
        last_content_item = stream_interactor.get_module(ContentItemStore.IDENTITY).get_latest(conversation) ?? ci;
        update_message_label();
        update_time_label();
        update_read();
    }

    public async void colapse() {
        main_revealer.set_transition_type(RevealerTransitionType.SLIDE_UP);
        main_revealer.set_reveal_child(false);

        // Animations can be diabled (=> child_revealed immediately false). Wait for completion in case they're enabled.
        if (main_revealer.child_revealed) {
            main_revealer.notify["child-revealed"].connect(() => {
                Idle.add(colapse.callback);
            });
            yield;
        }
    }

    protected void update_name_label() {
        name_label.label = Util.get_conversation_display_name(stream_interactor, conversation);
    }

    protected void update_time_label(DateTime? new_time = null) {
        if (last_content_item != null) {
            time_label.visible = true;
            time_label.label = get_relative_time(last_content_item.display_time.to_local());
        }
    }

    protected void update_message_label() {
        if (last_content_item != null) {
            switch (last_content_item.type_) {
                case MessageItem.TYPE:
                    MessageItem message_item = last_content_item as MessageItem;
                    Message last_message = message_item.message;

                    string body = last_message.body;
                    bool me_command = body.has_prefix("/me ");

                    /* If we have a /me command, we always show the display
                     * name, and we don't set me_is_me on
                     * get_participant_display_name, since that will return
                     * "Me" (internationalized), whereas /me commands expect to
                     * be in the third person. We also omit the colon in this
                     * case, and strip off the /me prefix itself. */

                    if (conversation.type_ == Conversation.Type.GROUPCHAT || me_command) {
                        nick_label.label = Util.get_participant_display_name(stream_interactor, conversation, last_message.from, !me_command);
                    } else if (last_message.direction == Message.DIRECTION_SENT) {
                        nick_label.label = _("Me");
                    } else {
                        nick_label.label = "";
                    }

                    if (me_command) {
                        /* Don't slice off the space after /me */
                        body = body.slice("/me".length, body.length);
                    } else if (nick_label.label.length > 0) {
                        /* TODO: Is this valid for RTL languages? */
                        nick_label.label += ": ";
                    }

                    message_label.attributes.filter((attr) => attr.equal(attr_style_new(Pango.Style.ITALIC)));
                    message_label.label = Util.summarize_whitespaces_to_space(body);

                    break;
                case FileItem.TYPE:
                    FileItem file_item = last_content_item as FileItem;
                    FileTransfer transfer = file_item.file_transfer;

                    if (conversation.type_ == Conversation.Type.GROUPCHAT) {
                        // TODO properly display nick for oneself
                        nick_label.label = Util.get_participant_display_name(stream_interactor, conversation, file_item.file_transfer.from, true) + ": ";
                    } else {
                        nick_label.label = transfer.direction == Message.DIRECTION_SENT ? _("Me") + ": " : "";
                    }

                    bool file_is_image = transfer.mime_type != null && transfer.mime_type.has_prefix("image");
                    message_label.attributes.insert(attr_style_new(Pango.Style.ITALIC));
                    if (transfer.direction == Message.DIRECTION_SENT) {
                        message_label.label = (file_is_image ? _("Image sent") : _("File sent") );
                    } else {
                        message_label.label = (file_is_image ? _("Image received") : _("File received") );
                    }
                    break;
            }
            nick_label.visible = true;
            message_label.visible = true;
        }
    }

    protected void update_read() {
        int current_num_unread = stream_interactor.get_module(ChatInteraction.IDENTITY).get_num_unread(conversation);
        if (num_unread == current_num_unread) return;
        num_unread = current_num_unread;

        if (num_unread == 0) {
            unread_count_label.visible = false;
        } else if (num_unread == -1 ){
            unread_count_label.label = "> 50";
            unread_count_label.visible = true;
        } else {
            unread_count_label.label = num_unread.to_string();
            unread_count_label.visible = true;
        }
    }

    protected Box get_fulljid_box(Jid full_jid) {
        Box box = new Box(Orientation.HORIZONTAL, 5) { visible=true };

        Show show = stream_interactor.get_module(PresenceManager.IDENTITY).get_last_show(full_jid, conversation.account);
        Image image = new Image() { visible=true };
        if (show.as == Show.AWAY) {
            image.set_from_icon_name("dino-status-away", IconSize.SMALL_TOOLBAR);
        } else if (show.as == Show.XA || show.as == Show.DND) {
            image.set_from_icon_name("dino-status-dnd", IconSize.SMALL_TOOLBAR);
        } else if (show.as == Show.CHAT) {
            image.set_from_icon_name("dino-status-chat", IconSize.SMALL_TOOLBAR);
        } else {
            image.set_from_icon_name("dino-status-online", IconSize.SMALL_TOOLBAR);
        }
        box.add(image);

        Label resource = new Label(full_jid.resourcepart) { visible=true };
        resource.xalign = 0;
        box.add(resource);
        box.show_all();
        return box;
    }

    public override void state_flags_changed(StateFlags flags) {
        StateFlags curr_flags = get_state_flags();
        if ((curr_flags & StateFlags.PRELIGHT) != 0) {
            time_revealer.set_reveal_child(false);
            xbutton_revealer.set_reveal_child(true);
        } else {
            time_revealer.set_reveal_child(true);
            xbutton_revealer.set_reveal_child(false);
        }
    }

    private Widget generate_tooltip() {
        Builder builder = new Builder.from_resource("/im/dino/Dino/conversation_selector/chat_row_tooltip.ui");
        Box main_box = builder.get_object("main_box") as Box;
        Box inner_box = builder.get_object("inner_box") as Box;
        Label jid_label = builder.get_object("jid_label") as Label;

        jid_label.label = conversation.counterpart.to_string();

        Gee.List<Jid>? full_jids = stream_interactor.get_module(PresenceManager.IDENTITY).get_full_jids(conversation.counterpart, conversation.account);
        if (full_jids != null) {
            for (int i = 0; i < full_jids.size; i++) {
                inner_box.add(get_fulljid_box(full_jids[i]));
            }
        }
        return main_box;
    }

    private static string get_relative_time(DateTime datetime) {
         DateTime now = new DateTime.now_local();
         TimeSpan timespan = now.difference(datetime);
         if (timespan > 365 * TimeSpan.DAY) {
             return datetime.get_year().to_string();
         } else if (timespan > 7 * TimeSpan.DAY) {
             // Day and month
             // xgettext:no-c-format
             return datetime.format(_("%b %d"));
         } else if (timespan > 2 * TimeSpan.DAY) {
             return datetime.format("%a");
         } else if (datetime.get_day_of_month() != now.get_day_of_month()) {
             return _("Yesterday");
         } else if (timespan > 9 * TimeSpan.MINUTE) {
             return datetime.format(Util.is_24h_format() ?
                /* xgettext:no-c-format */ /* Time in 24h format (w/o seconds) */ _("%H∶%M") :
                /* xgettext:no-c-format */ /* Time in 12h format (w/o seconds) */ _("%l∶%M %p"));
         } else if (timespan > 1 * TimeSpan.MINUTE) {
             ulong mins = (ulong) (timespan.abs() / TimeSpan.MINUTE);
             return n("%i min ago", "%i mins ago", mins).printf(mins);
         } else {
             return _("Just now");
         }
    }
}

}
