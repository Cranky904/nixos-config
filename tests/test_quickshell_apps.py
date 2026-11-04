"""Open-window grid, real tray actions and isolated per-app hover gradients."""
import unittest
from pathlib import Path
import tempfile

from test_quickshell_visibility import QmlScenarioTests


class AppsDetailsTests(QmlScenarioTests):
    component_name = "AppsDetails"
    dependencies = ("AppWindowButton", "AppTrayButton", "FrostedSurface", "HoverOutline", "PlaylistScrollBar", "WorkspaceBadge")

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.controller = cls.controller.replace("property bool active: false", "property bool active: true")
        cls.controller = cls.controller.replace("required property var window", '''
        property var retained: null
        property int activated: 0
        property var window: QtObject {
            property var windows: []
            property var icons: ({})
            property int workspace: 1
            property string selectedAddress: "0xa"
            property string focused: ""
            property string closed: ""
            function focusWindow(address) { focused=address; }
            function closeWindow(address) { closed=address; }
        }''')

    def test_all_workspaces_stay_in_the_grid_and_only_tray_items_use_the_rail(self):
        self.run_scenario('''
            function row(address,workspace,pinned=false) {return {key:address,address:address,
                title:"Title",className:"kitty",appName:"Kitty",workspace:workspace,pinned:pinned};}
            state.window.windows=[row("0xa",1),row("0xb",2),row("0xc",2,true),row("0xd",-99)];
            state.trayItems=[{id:"steam",title:"Steam",icon:"",hasMenu:false,onlyMenu:false,
                activate:()=>state.activated++}];
            check(state.windowsModel.count===4,"all open windows, including other workspaces, use full tiles");
            check(state.trayCount===1,"the rail contains actual tray registrations");
            state.window.workspace=2;
            check(state.windowsModel.count===4,"switching workspace cannot hide or move grid windows");
            state.window.windows=[];
            check(state.windowsModel.count===0 && state.trayCount===1,"a windowless tray app remains in the rail");
            state.trayItems=[];check(state.trayCount===0,"unregistered tray items disappear");
        ''')

    def test_title_and_icon_updates_preserve_tiles_and_actions_target_each_window(self):
        self.run_scenario('''
            function find(item,name) {if(item.objectName===name)return item;
                for(const child of item.children || []){const match=find(child,name);if(match)return match;}return null;}
            state.motionEnabled=false;
            state.window.windows=[{key:"one",address:"0xa",title:"First",className:"kitty",workspace:1},
                {key:"two",address:"0xb",title:"Second",className:"chromium",workspace:2}];
            state.retained=find(state,"app-0xa");
            check(!!state.retained,"full tile exists");
            const other=find(state,"app-0xb");
            other.clicked();check(state.window.focused==="0xb","another workspace window focuses its own address");
            other.closeRequested();check(state.window.closed==="0xb","another workspace window closes its own address");
            state.retained.clicked();check(state.window.focused==="0xa","grid focuses its own address");
            state.retained.closeRequested();check(state.window.closed==="0xa","grid closes its own address");
            state.window.windows=[{key:"one",address:"0xa",title:"Changed",className:"kitty",workspace:1}];
            state.window.icons=({one:"file:///missing-test-icon.svg"});
        ''', later='''
            function find(item,name) {if(item.objectName===name)return item;
                for(const child of item.children || []){const match=find(child,name);if(match)return match;}return null;}
            check(state.retained===find(state,"app-0xa"),"metadata refresh preserves the hovered delegate");
            check(state.retained.windowData.title==="Changed","title updates in place");
            check(String(state.retained.iconSource).endsWith("missing-test-icon.svg"),"icons update independently of window identity");
            check(state.windowsModel.count===1,"closing a window removes only its tile");
        ''')

    def test_overflow_scrolls_and_glass_sampling_tracks_scroll(self):
        self.run_scenario('''
            const rows=[];
            for(let i=0;i<20;++i) rows.push({key:String(i),address:"0x"+i.toString(16),
                title:"Window "+i,className:"kitty",workspace:i<12?1:2});
            state.window.windows=rows;
            state.trayItems=Array.from({length:8},(_,i)=>({id:"tray"+i,title:"Tray app",icon:"",hasMenu:false,onlyMenu:false}));
        ''', later='''
            function find(item,name) {if(item.objectName===name)return item;
                for(const child of item.children || []){const match=find(child,name);if(match)return match;}return null;}
            const grid=find(state,"windowApps"),rail=find(state,"trayApps");
            // Positioners normally polish with a window; this controller fixture
            // has no surface, so explicitly run their pending layout first.
            for (const view of [grid,rail])
                view.contentItem.children.find(child=>typeof child.forceLayout==="function").forceLayout();
            check(grid.contentHeight>grid.height && rail.contentHeight>rail.height,"both areas support overflow");
            const tile=find(state,"app-0x0"),revision=tile.glass.revision;
            grid.contentY=80;
            check(tile.glass.layout[3]===80,"live glass crop follows the scrolled tile");
            state.window.windows=state.window.windows.map(w=>Object.assign({},w,{title:w.title+" updated"}));
            check(grid.contentY===80,"metadata updates preserve scroll position");
        ''')


class AppsActionsTests(QmlScenarioTests):
    component_name = "WindowService"

    def test_middle_close_targets_only_a_live_window_and_preserves_active_selection(self):
        self.run_scenario('''
            state.requested=false;state.workspace=1;
            state.clients=[{address:"0xa",pid:11,class:"kitty",workspace:{id:1}},
                {address:"0xb",pid:12,class:"kitty",workspace:{id:2}},
                {address:"0xc",pid:13,class:"kitty",workspace:{id:1},mapped:false}];
            state.focused=state.clients[0];state.refresh();
            const commands=[];state.dispatchRequested.connect(command=>commands.push(command));
            state.closeWindow("0xb");state.focusWindow("0xb");
            state.closeWindow("0xc");state.closeWindow("0xdead");state.closeWindow("0xa; quit");
            check(commands.join("|")==='hl.dsp.window.close({window="address:0xb"})|hl.dsp.focus({window="address:0xb"})',
                "nonactive live windows can be focused/closed; stale, unmapped and malformed targets cannot");
            check(state.selectedAddress==="0xa","middle close does not silently change the active target");
            state.closeWindow();check(commands[2]==='hl.dsp.window.close({window="address:0xa"})',"header close retains its original behavior");
        ''')


class AppsSelectionTests(QmlScenarioTests):
    component_name = "ExpandedState"

    def test_apps_selects_replaces_and_retracts_through_the_shared_module_state(self):
        self.run_scenario('''
            state.motionEnabled=false;state.openWith("");state.select("apps");
            check(state.selected==="apps","Apps is a module");
            state.select("media");check(state.selected==="media","Media replaces Apps");
            state.select("apps");state.select("apps");
            check(state.open && state.selected==="","second selection retracts Apps within the open menu");
        ''')


class AppWindowButtonInputTests(QmlScenarioTests):
    component_name = "AppWindowButton"
    dependencies = ("FrostedSurface", "HoverOutline", "WorkspaceBadge")

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.dependency_sources["IndependentAppTile"] = cls.controller
        assets=tempfile.TemporaryDirectory(prefix="apps-icon-colors-")
        cls.addClassCleanup(assets.cleanup)
        for color in ("red","blue"):
            (Path(assets.name)/(color+".svg")).write_text(
                f'<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48"><rect width="48" height="48" fill="{color}"/></svg>')
        cls.controller = cls.controller.replace("required property var windowData",
            'property var windowData: ({title:"Test window",appName:"Kitty",className:"kitty",workspace:3})')
        cls.controller = cls.controller.replace("signal closeRequested()", '''signal closeRequested()
            onClicked: fixture.focusCount++
            onCloseRequested: fixture.closeCount++''')
        cls.controller = cls.controller.replace('property url iconSource: ""',
            f'property url iconSource: "{(Path(assets.name)/"red.svg").as_uri()}"', 1)
        cls.controller = cls.controller.replace("AbstractButton {", '''import QtTest
        Scope {
            id: fixture
            property int focusCount: 0
            property int closeCount: 0
            function checkHover() {
                function near(a,b) {return Math.abs(a.r-b.r)<0.005 && Math.abs(a.g-b.g)<0.005 && Math.abs(a.b-b.b)<0.005;}
                input.mouseMove(button,280,140);input.wait(260);
                if (!(button.iconTint.r>button.iconTint.b && neighbor.iconTint.b>neighbor.iconTint.r))
                    throw new Error("each tile samples its own icon color");
                input.mouseMove(button,30,30);input.wait(100);
                if (!(button.hoverProgress>0 && button.hoverProgress<1)) throw new Error("hover eases through intermediate colors");
                input.wait(260);
                if (!near(button.trailingTint,button.iconTint)) throw new Error("hover fills the tile with its icon tint");
                if (!near(neighbor.trailingTint,neighbor.neutralTint)) throw new Error("neighbor keeps its own resting gradient");
                const transform=button.contentItem.children[0].children[0];
                if (transform.rotation!==0 || transform.scale<=1) throw new Error("icons enlarge without rotation");
                input.mouseMove(button,280,140);input.wait(70);
                if (!(button.hoverProgress>0 && button.hoverProgress<1)) throw new Error("departure eases back toward gray");
                input.wait(230);
                if (!near(button.trailingTint,button.neutralTint)) throw new Error("resting gradient returns");
                button.motionEnabled=false;
                input.mouseMove(button,30,30);
                if (button.hoverProgress!==1) throw new Error("reduced motion settles immediately");
            }
            function exercise(compact) {
                button.compact=compact;
                input.mouseClick(button,30,30,Qt.LeftButton);
                input.mouseClick(button,30,30,Qt.MiddleButton);
            }
            FloatingWindow {
                visible:true;implicitWidth:600;implicitHeight:180
                AbstractButton {''', 1)
        cls.controller += '''
            IndependentAppTile {
                id:neighbor;x:320
                windowData:({title:"Other",appName:"Other",workspace:2})
                iconSource:Quickshell.iconPath("@BLUE_ICON@")
            }
        }
        TestCase {id:input;when:false;optional:true}
        }
        '''
        cls.controller = cls.controller.replace("@BLUE_ICON@", str(Path(assets.name)/"blue.svg"))

    def test_real_pointer_events_keep_focus_and_close_distinct_in_both_tile_sizes(self):
        self.run_scenario("", later='''
            state.exercise(false);
            check(state.focusCount===1 && state.closeCount===1,"full tile routes left and middle clicks separately");
            state.exercise(true);
            check(state.focusCount===2 && state.closeCount===2,"icon rail routes the same pointer actions");
        ''', delay=300)


    def test_icon_tints_stay_separate_and_hover_enlarges_without_rotation(self):
        self.run_scenario("", later="state.checkHover();", delay=400)


class AppTrayButtonTests(QmlScenarioTests):
    component_name = "AppTrayButton"
    dependencies = ("AppWindowButton", "FrostedSurface", "HoverOutline", "WorkspaceBadge")

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.controller = cls.controller.replace("required property var trayItem", '''
            property int activationCount:0
            property int menuCount:0
            property int quitCount:0
            property var fixtureEntries:[]
            property var trayItem:({id:"steam",title:"Steam",icon:"",hasMenu:true,menu:null,onlyMenu:false,
                activate:()=>button.activationCount++,display:()=>button.menuCount++})''')
        cls.controller = cls.controller.replace("quitEntry(menu.children.values)", "quitEntry(fixtureEntries)")

    def test_tray_activation_and_explicit_quit_do_not_use_window_addresses(self):
        self.run_scenario('''
            state.clicked();check(state.activationCount===1,"left click activates the real tray app");
            state.fixtureEntries=[{text:"Exit fullscreen",enabled:true,isSeparator:false,hasChildren:false},
                {text:"E&xit Steam",enabled:true,isSeparator:false,hasChildren:false,triggered:()=>state.quitCount++}];
            state.closeRequested();
            check(state.quitCount===1 && !state.closePending,"middle click invokes the explicit app exit action");
            check(state.activationCount===1,"middle close never toggles or restores the app");
            state.active=false;state.clicked();state.closeRequested();
            check(state.activationCount===1 && state.quitCount===1,"hidden menu cannot dispatch tray actions");
        ''')

    def test_private_tray_icon_paths_are_preserved_and_missing_theme_icons_fall_back(self):
        self.run_scenario('''
            const privateIcon="image://icon/steam_tray?path=/tmp/app-private-icons";
            state.trayItem=Object.assign({},state.trayItem,{icon:privateIcon});
            check(String(state.iconSource)===privateIcon,"preserve the app's private icon search path");
            state.trayItem=Object.assign({},state.trayItem,{icon:"image://icon/quickshell-test-nonexistent-icon"});
            check(String(state.iconSource)==="","a missing theme icon uses the regular app fallback");
        ''')

    def test_missing_or_disabled_quit_opens_menu_and_close_cancels_pending_action(self):
        self.run_scenario('''
            state.fixtureEntries=[{text:"Quit",enabled:false,isSeparator:false,hasChildren:false},
                {text:"Exit fullscreen",enabled:true,isSeparator:false,hasChildren:false}];
            state.closeRequested();check(state.closePending,"wait for asynchronously loaded menu entries");
        ''', later='''
            check(state.menuCount===1 && !state.closePending,"without a usable Quit action open the app menu");
            state.closeRequested();state.active=false;
            check(!state.closePending,"closing Apps cancels pending tray quit");
        ''', delay=650)


if __name__ == "__main__":
    unittest.main()
