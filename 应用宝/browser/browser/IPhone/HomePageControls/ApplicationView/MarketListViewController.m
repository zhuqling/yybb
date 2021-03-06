//
//  MarketListViewController.m
//  browser
//
//  Created by liguiyang on 14-10-8.
//
//

#import "MarketListViewController.h"
#import "PublicTableViewCell.h"
#import "TableViewLoadingCell.h"
#import "SearchResult_DetailViewController.h"
#import "CollectionViewBack.h"
#import "EGORefreshTableHeaderView.h"
#import "AlertLabel.h"

#import "MarketServerManage.h"
#import "AppStatusManage.h"

#define RankingListType @"RankingListType"
#define TAG_NORMAL_CELL 200
#define TAG_OTHER_CELL 201

@interface MarketListViewController ()<UITableViewDataSource,UITableViewDelegate,MarketServerDelegate,EGORefreshTableHeaderDelegate>
{
    NSString *identifier;
    NSString *identifier_NoCache;
    //
    int  pageNumber; // 请求第几页数据
    BOOL hasMoreDataFlag; // 是否有下一页数据
    NSMutableArray *listData;
    NSMutableArray *exposureDataArray; // 曝光数据
    
    MarketListType listType; // 设置数据源
    CellRequestStyle loadingStyle; // loaidngCell状态
    
    BOOL couldUpwardRequest;// 是否可以上拉刷新
    BOOL scrollEndFlag; // 是否滚动停止
    BOOL hasReceivedFailedFlag; //是否返回失败数据
    BOOL hasExecCodeOnce; // 滑动曝光一次
    
    SearchResult_DetailViewController *appDetailVC; // 应用详情
    CollectionViewBack *backView;
    AlertLabel *alertLabel; // 下拉刷新失败label
    EGORefreshTableHeaderView *egoRefreshView;
    BOOL isRefreshing;
    
}

@property (nonatomic, strong) UITableView *tableView;

@end

static NSString *loadingCellIden = @"loadingCellIdentifier";

@implementation MarketListViewController

-(id)initWithMarketListType:(MarketListType)marketListType
{
    self = [super init];
    if (self) {
        listType = marketListType;
        loadingStyle = CellRequestStyleLoading;
        pageNumber = 1;
        listData = [NSMutableArray array];
        exposureDataArray = [NSMutableArray array];
        identifier = [NSString stringWithFormat:@"marketList_%d",listType];
        identifier_NoCache = [NSString stringWithFormat:@"NoCache_ML%d",listType];
    }
    
    return self;
}

#pragma mark - Utility

-(void)initializationUserInterfaceAndRequest
{
    [self setBackViewStatus:Loading];
    NSString *title = [self requestListData];
    
    if (![title isEqualToString:RankingListType]) {
        addNavgationBarBackButton(self, popListViewController);
        
        self.navigationItem.title = title;
        
        
    }
}

-(void)removeListener
{
    [[MarketServerManage getManager] removeListener:self];
}

-(void)popListViewController
{
    [self.navigationController popViewControllerAnimated:YES];
    [[MarketServerManage getManager] removeListener:self];
}

-(void)showDetailViewController:(NSInteger)row
{
    NSString *source = [self getSourceStringBy:listType andIndex:row];
    [appDetailVC setAppSoure:APP_DETAIL(source)];
    appDetailVC.view.hidden = NO;
    [appDetailVC hideDetailTableView];
    appDetailVC.BG.hidden = NO;
    [appDetailVC beginPrepareAppContent:listData[row]];
    [self.navigationController pushViewController:appDetailVC animated:YES];
    
    // 汇报点击
    [[ReportManage instance] ReportAppDetailClick:APP_DETAIL(source) appid:[listData[row] objectForKey:@"appid"]];
}

-(void)execFailedOpearation:(NSInteger)pageCount userData:(NSString *)userData
{
    if (![userData isEqual:identifier] && ![userData isEqual:identifier_NoCache]) return;
    
    // 下拉刷新请求失败
    if ([userData isEqual:identifier_NoCache]) {
        [self showDownRefreshFailedLabel];
        return;
    }
    
    //
    if (pageCount==1) {
        if (userData == identifier) { // 有缓存的请求首页数据
            [self setBackViewStatus:Failed];
        }
        return ;
    }
    
    // 上拉刷新失败
    hasReceivedFailedFlag = YES;
    if (scrollEndFlag) {
        [self setUpPullRefreshFailedView];
    }
}

-(void)setBackViewStatus:(Request_status)status
{
    backView.status = status;
//    self.tableView.scrollEnabled = (status==Hidden)?YES:NO;
}

-(void)reloadLoadingCell:(CellRequestStyle)style
{
    if (hasMoreDataFlag) {
        loadingStyle = style;
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:listData.count inSection:1]] withRowAnimation:UITableViewRowAnimationNone];
    }
}


-(BOOL)isMarkRankingListType
{ // 是否是 应用或游戏排行旁以及免费应用游戏
    if (listType==marketList_AppWeekRankingType
        || listType==marketList_AppMonthRankingType
        || listType==marketList_AppTotalRankingType
        || listType==marketList_GameWeekRankingType
        || listType==marketList_GameMonthRankingType
        || listType==marketList_GameTotalRankingType
        || listType == marketList_NewAddFreeApp
        || listType == marketList_NewAddFreeGame) {
        return YES;
    }
    
    return NO;
}

-(void)setListDataSource:(NSDictionary *)dataDic userData:(id)userData
{
    // 1
    NSString *flagStr = [[dataDic objectForKey:@"flag"] objectForKey:@"dataend"];
    hasMoreDataFlag = [flagStr isEqualToString:@"y"]?YES:NO;
    couldUpwardRequest = hasMoreDataFlag;
    
    if ([userData isEqual:identifier_NoCache]|| ([userData isKindOfClass:[NSDictionary class]]&&[[(NSDictionary *)userData objectForKey:@"isEGORefreshResult"] boolValue])){ // 下拉刷新成功
        [listData removeAllObjects];
        pageNumber = 1;
    }
    
    // 2、展示数据
    [listData addObjectsFromArray:[dataDic objectForKey:@"data"]];
    [self.tableView reloadData];
    
    // 3、
    pageNumber++;
}


-(void)setUpPullRefreshFailedView
{
    couldUpwardRequest = YES;
    scrollEndFlag = NO;
    hasReceivedFailedFlag = NO;
    // UI
    [self reloadLoadingCell:CellRequestStyleFailed];
}

-(void)hideDownPullRefreshView
{
    isRefreshing = NO;
    [egoRefreshView egoRefreshScrollViewDataSourceDidFinishedLoading:self.tableView];
}

-(NSString *)getSourceStringBy:(MarketListType)type andIndex:(NSInteger)row
{ // 设置数据源
    NSString *sourceStr = nil;
    
    switch (type) {
        case marketList_AppHotType:
            sourceStr = HOT_APP(row);
            break;
        case marketList_AppLatestType:
            sourceStr = NEW_APP(row);
            break;
        case marketList_AppWeekRankingType:
            sourceStr = APP_WEEK_RANKING(row);
            break;
        case marketList_AppMonthRankingType:
            sourceStr = APP_MONTH_RANKING(row);
            break;
        case marketList_AppTotalRankingType:
            sourceStr = APP_TOTAL_RANKING(row);
            break;
        case marketList_GameHotType:
            sourceStr = HOT_GAME(row);
            break;
        case marketList_GameLatestType:
            sourceStr = NEW_GAME(row);
            break;
        case marketList_GameFengCeType:
            sourceStr = FENGCE_GAME(row);
            break;
        case marketList_GameWeekRankingType:
            sourceStr = GAME_WEEK_RANKING(row);
            break;
        case marketList_GameMonthRankingType:
            sourceStr = GAME_MONTH_RANKING(row);
            break;
        case marketList_GameTotalRankingType:
            sourceStr = GAME_TOTAL_RANKING(row);
            break;
        case marketList_NewAddFreeApp:
            sourceStr = APP_FREE(row);
            break;
        case marketList_NewAddFreeGame:
            sourceStr = GAME_FREE(row);
            break;
        default:
            break;
    }
    
    return sourceStr;
}

-(void)reportExposureData
{
    [exposureDataArray removeAllObjects];
    
    for (UITableViewCell *cell in self.tableView.visibleCells) {
        if (cell.tag == TAG_NORMAL_CELL) {
            [exposureDataArray addObject:((PublicTableViewCell*)cell).appID];
        }
    }
    
    if (exposureDataArray.count > 0) {
        NSString *sourceStr = [self getSourceStringBy:listType andIndex:-1];
        [[ReportManage instance] ReportAppBaoGuang:sourceStr appids:exposureDataArray];
    }
}

-(void)showDownRefreshFailedLabel
{
    CGFloat originY = (IOS7)?64:0;
    [alertLabel startAnimationFromOriginY:originY];
}

#pragma mark - Life Cycle
- (void)viewDidLoad {
    [super viewDidLoad];
    
    // UI
    self.view.backgroundColor = [UIColor whiteColor];
    if (IOS7) {
        self.automaticallyAdjustsScrollViewInsets = NO;
    }
    
    // UITableView
    UITableView *tabView = [[UITableView alloc] init];
    tabView.separatorStyle = UITableViewCellSeparatorStyleNone;
    tabView.dataSource = self;
    tabView.delegate = self;
    [self.view addSubview:tabView];
    self.tableView = tabView;
    
    // pullRefresh loading
    egoRefreshView = [[EGORefreshTableHeaderView alloc] initWithFrame:CGRectZero];
    egoRefreshView.egoDelegate = self;
    egoRefreshView.inset = UIEdgeInsetsZero;
    [self.tableView addSubview:egoRefreshView];
    
    // tap loading
    __weak id mySelf = self;
    backView = [[CollectionViewBack alloc] init];
    [backView setClickActionWithBlock:^{
        [mySelf performSelector:@selector(initRequest) withObject:nil afterDelay:delayTime];
    }];
    [self.view addSubview:backView];
    
    // 下拉刷新失败
    alertLabel = [[AlertLabel alloc] init];
    [self.view addSubview:alertLabel];
    
    // 详情
    appDetailVC = [[SearchResult_DetailViewController alloc] init];
    
    [[MarketServerManage getManager] addListener:self];
    [self initializationUserInterfaceAndRequest];// 初始化请求
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

-(void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    if (self.navigationController.viewControllers.count == 1) {
        // 滑动返回移除监听
        [[MarketServerManage getManager] removeListener:self];
    }
}

-(void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    
    CGFloat topHeight = (IOS7)?64:0;
    CGFloat width = self.view.frame.size.width;
    CGFloat height = self.view.frame.size.height;
    
    
    self.tableView.frame = self.view.bounds;
    egoRefreshView.frame = CGRectMake(0, -height+topHeight, width, height);
    backView.frame = _tableView.frame;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

-(void)dealloc
{
    self.tableView.delegate = nil;
    self.tableView.dataSource = nil;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0 || section == 2) return 1;
    
    return (hasMoreDataFlag)?listData.count+1:listData.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        if (indexPath.row < listData.count) {
            static NSString *CellIdentifier = @"informationCellIden";
            PublicTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
            
            if (!cell) {
                cell = [[PublicTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
                cell.tag = TAG_NORMAL_CELL;
            }
            
            // 设置数据源
            cell.downLoadSource = [self getSourceStringBy:listType andIndex:indexPath.row];
            NSDictionary *appInfor = listData[indexPath.row];
            NSNumber *number = [appInfor objectForKey:@"appreputation"];
            NSString *reputation = [NSString stringWithFormat:@"%@",number];
            [cell initCellInfoDic:appInfor];
            [cell setNameLabelText:[appInfor objectForKey:@"appname"]];
            [cell setGoodNumberLabelText: reputation];
            [cell setDownloadNumberLabelText:[appInfor objectForKey:@"appdowncount"]];
            [cell setLabelType:[appInfor objectForKey:@"category"] Size:[appInfor objectForKey:@"appsize"]];
            [cell setDetailText:[appInfor objectForKey:@"appintro"]];
            cell.appVersion = [appInfor objectForKey:@"appversion"];
            cell.iconURLString = [appInfor objectForKey:@"appiconurl"];
            cell.previewURLString = [appInfor objectForKey:@"apppreview"];
            //按钮状态显示
            cell.appID = [appInfor objectForKey:@"appid"];
            cell.plistURL = [appInfor objectForKey:@"plist"];
            
            if (self.isFreeCell) {
                [cell setPrice];
            }
            
            if ([self isMarkRankingListType]) {
                [cell setAngleNumber:indexPath.row];
            }
            
            [cell initDownloadButtonState];
            
            //加载图片
            [cell.iconImageView sd_setImageWithURL:[NSURL URLWithString:cell.iconURLString] placeholderImage:_StaticImage.icon_60x60];
            cell.backgroundColor = [UIColor clearColor];
            
            return cell;
        }
        
        // loadingCell
        TableViewLoadingCell *loadingCell = [tableView dequeueReusableCellWithIdentifier:loadingCellIden];
        if (loadingCell == nil) {
            loadingCell = [[TableViewLoadingCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:loadingCellIden];
            loadingCell.tag = TAG_OTHER_CELL;
        }
        
        loadingCell.style = loadingStyle;
        
        return loadingCell;
    }
    
    // section == 0 || section==2
    static NSString *headCellIden = @"HeaderCellIdentifier";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:headCellIden];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:headCellIden];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.tag = TAG_OTHER_CELL;
    }
    
    return cell;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        
        if ([self isMarkRankingListType]) {
            if (self.delegate && [self.delegate respondsToSelector:@selector(aCellHasBeenSelected:)]) {
                
                if ([listData count] == indexPath.row) {
                    return;
                }
                NSString *source = [self getSourceStringBy:listType andIndex:indexPath.row];
                NSDictionary *infoDic = @{@"data":listData[indexPath.row],@"source":source};
                [self.delegate aCellHasBeenSelected:infoDic];
            }
        }
        else
        {
            [self showDetailViewController:indexPath.row];
        }
    }
}

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) return IOS7?64:0;
    if (indexPath.section == 2){
        if (!hasMoreDataFlag) {
            return BOTTOM_HEIGHT;
        }
        
        return 0.0;
    }
    
    if (hasMoreDataFlag && indexPath.row==listData.count) {
        return 44+BOTTOM_HEIGHT;
    }
    
    return PUBLICNOMALCELLHEIGHT;
}

#pragma mark - UISollViewDelegate

-(void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [egoRefreshView egoRefreshScrollViewDidScroll:scrollView];
    //
    CGFloat offset = self.view.frame.size.height+45;
    if (couldUpwardRequest && scrollView.contentSize.height-scrollView.contentOffset.y<offset) {
        couldUpwardRequest = NO;
        [self requestListData];
        [self reloadLoadingCell:CellRequestStyleLoading];
    }
}

-(void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    [egoRefreshView egoRefreshScrollViewDidEndDragging:scrollView];
    //
    hasExecCodeOnce = NO;
    if (!decelerate) {
        hasExecCodeOnce = YES;
        [self reportExposureData]; // 曝光
        
        // 展示失败view
        scrollEndFlag = YES;
        if (hasReceivedFailedFlag) {
            [self setUpPullRefreshFailedView];
        }
    }
}

-(void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    if (!hasExecCodeOnce) {
        [self reportExposureData]; // 曝光
        
        // 展示失败view
        scrollEndFlag = YES;
        if (hasReceivedFailedFlag) {
            [self setUpPullRefreshFailedView];
        }
    }
}

-(void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset
{
    if (scrollView.contentOffset.y<-(_tableView.contentInset.top+65)) {
        *targetContentOffset = scrollView.contentOffset;
    }
}

#pragma mark - EGORefreshViewDelegate

- (void)egoRefreshTableHeaderDidTriggerRefresh:(EGORefreshTableHeaderView*)view
{
    if (isRefreshing) return;
    
    // 无缓存的请求
    isRefreshing = YES;
    [self performSelector:@selector(requestListDataNoCache) withObject:nil afterDelay:delayTime];
}

- (BOOL)egoRefreshTableHeaderDataSourceIsLoading:(EGORefreshTableHeaderView*)view
{
    return isRefreshing;
}

#pragma mark - Public Request

-(void)initRequest
{
    pageNumber = 1;
    [listData removeAllObjects];
    
    // 请求
    [self setBackViewStatus:Loading];
    [self requestListData];
}

-(NSString *)requestListData
{
    NSString *listTilte = RankingListType;
    
    switch (listType) {
        case marketList_AppHotType:
            listTilte = @"最热应用";
            [self requestHotAppList];
            break;
        case marketList_AppLatestType:
            listTilte = @"最新应用";
            [self requestLatestAppList];
            break;
        case marketList_AppWeekRankingType:
            [self requestAppRankingList:marketList_AppWeekRankingType];
            break;
        case marketList_AppMonthRankingType:
            [self requestAppRankingList:marketList_AppMonthRankingType];
            break;
        case marketList_AppTotalRankingType:
            [self requestAppRankingList:marketList_AppTotalRankingType];
            break;
        case marketList_GameHotType:
            listTilte = @"最热游戏";
            [self requestHotGameList];
            break;
        case marketList_GameLatestType:
            listTilte = @"最新游戏";
            [self requestLatestGameList];
            break;
        case marketList_GameFengCeType:
            listTilte = @"封测网游";
            [self requestFengCeGameList];
            break;
        case marketList_GameWeekRankingType:
            [self requestGameRankingList:marketList_GameWeekRankingType];
            break;
        case marketList_GameMonthRankingType:
            [self requestGameRankingList:marketList_GameMonthRankingType];
            break;
        case marketList_GameTotalRankingType:
            [self requestGameRankingList:marketList_GameTotalRankingType];
            break;
        case marketList_NewAddFreeApp:
            [self requestFreeType:@"app" isEGORefreshing:NO];
            listTilte = @"应用";
            break;
        case marketList_NewAddFreeGame:
            [self requestFreeType:@"game" isEGORefreshing:NO];
            listTilte = @"游戏";
            break;
        default:
            break;
    }
    
    return listTilte;
}

-(void)requestListDataNoCache
{
    // 动画
    [self hideDownPullRefreshView];
    
    switch (listType) {
        case marketList_AppHotType:
            [[MarketServerManage getManager] requestAppColumnHotAllList:1 userData:identifier_NoCache];
            break;
        case marketList_AppLatestType:
            [[MarketServerManage getManager] requestAppColumnNewAllList:1 userData:identifier_NoCache];
            break;
        case marketList_AppWeekRankingType:
            [[MarketServerManage getManager] requestAppRankingListColumn:WEEK_RANKING_LIST pageCount:1 userData:identifier_NoCache];
            break;
        case marketList_AppMonthRankingType:
            [[MarketServerManage getManager] requestAppRankingListColumn:MONTH_RANKING_LIST pageCount:1 userData:identifier_NoCache];
            break;
        case marketList_AppTotalRankingType:
            [[MarketServerManage getManager] requestAppRankingListColumn:TOTAL_RANKING_LIST pageCount:1 userData:identifier_NoCache];
            break;
        case marketList_GameHotType:
            [[MarketServerManage getManager] requestGameColumnHotAllList:1 userData:identifier_NoCache];
            break;
        case marketList_GameLatestType:
            [[MarketServerManage getManager] requestGameColumnNewAllList:1 userData:identifier_NoCache];
            break;
        case marketList_GameFengCeType:
            [[MarketServerManage getManager] requestGameColumnFengCeBetaGameAllList:1 userData:identifier_NoCache];
            break;
        case marketList_GameWeekRankingType:
            [[MarketServerManage getManager] requestGameRankingListColumn:WEEK_RANKING_LIST pageCount:1 userData:identifier_NoCache];
            break;
        case marketList_GameMonthRankingType:
            [[MarketServerManage getManager] requestGameRankingListColumn:MONTH_RANKING_LIST pageCount:1 userData:identifier_NoCache];
            break;
        case marketList_GameTotalRankingType:
            [[MarketServerManage getManager] requestGameRankingListColumn:TOTAL_RANKING_LIST pageCount:1 userData:identifier_NoCache];
            break;
        case marketList_NewAddFreeApp:
            pageNumber = 1;
            [self requestFreeType:@"app" isEGORefreshing:YES];
            break;
        case marketList_NewAddFreeGame:
            pageNumber = 1;
            [self requestFreeType:@"game" isEGORefreshing:YES];
            break;
            
        default:
            break;
    }
}

#pragma mark - 数据检测（列表数据）

- (BOOL)checkListData:(NSDictionary *)dic
{
    if (![dic getNSArrayObjectForKey:@"data"]) return NO;
    
    NSArray *tmpArray = [dic getNSArrayObjectForKey:@"data"];
    for (int i = 0; i < [tmpArray count]; i++) {
        
        NSDictionary *tmpDic = [tmpArray objectAtIndex:i];
        if(!IS_NSDICTIONARY(tmpDic))
            return NO;
        
        if (!([tmpDic getNSStringObjectForKey:@"appdowncount" ] &&
              [tmpDic getNSStringObjectForKey:@"appintro" ] &&
              [tmpDic getNSStringObjectForKey:@"appname" ] &&
              [tmpDic getNSStringObjectForKey:@"appreputation" ] &&
              [tmpDic getNSStringObjectForKey:@"appsize" ] &&
              [tmpDic getNSStringObjectForKey:@"appupdatetime" ] &&
              [tmpDic getNSStringObjectForKey:@"appversion" ] &&
              [tmpDic getNSStringObjectForKey:@"category" ] &&
              [tmpDic getNSStringObjectForKey:@"ipadetailinfor" ] &&
              [tmpDic getNSStringObjectForKey:@"plist" ] &&
              [tmpDic getNSStringObjectForKey:@"share_url" ] &&
              [tmpDic getNSStringObjectForKey:@"appiconurl" ] &&
              [tmpDic getNSStringObjectForKey:@"appid" ])) {
            
            return NO;
        }
    }
    return YES;
}

- (BOOL)checkFlag:(NSDictionary *)dic
{
    NSDictionary *tmpDic = [dic getNSDictionaryObjectForKey:@"flag"];
    if(!tmpDic)
        return NO;
    
    if (!([tmpDic getNSStringObjectForKey:@"dataend" ] &&
          [tmpDic getNSNumberObjectForKey:@"expire" ] &&
          [tmpDic getNSStringObjectForKey:@"md5" ])) {
        
        return NO;
    }
    return YES;
}
#pragma mark - 新增功能区_免费

- (void)requestFreeType:(NSString *)freeType isEGORefreshing:(BOOL)is{
    [[MarketServerManage getManager] requestFreeAppOrGame:pageNumber type:freeType userData:@{@"listType":[NSNumber numberWithInteger:listType],@"isEGORefreshResult":[NSNumber numberWithBool:is]} isUseCache:NO];

}
- (void)requestFreeAppOrGameSucess:(NSDictionary*)dataDic page:(int)page type:(NSString*)type userData:(id)userData{
    if (![userData isKindOfClass:[NSDictionary class]]|| listType != [(NSNumber *)[(NSDictionary *)userData objectForKey:@"listType"] integerValue]) {
        return;
    }
    
    
    if (![_StaticImage checkAppList:dataDic]){
        [self requestFreeAppOrGameFail:page type:type userData:userData];
        return;
    }
    
//    if ([[[dataDic objectForKey:@"flag"] objectForKey:@"dataend"] isEqualToString:@"n"]) {
//        //
//    }else{
//        //
//    }
    
    NSString *flagStr = [[dataDic objectForKey:@"flag"] objectForKey:@"dataend"];
    hasMoreDataFlag = [flagStr isEqualToString:@"y"]?YES:NO;
    couldUpwardRequest = hasMoreDataFlag;
    
    [self setListDataSource:dataDic userData:userData];
    
    // 第一次
    if (page == 1) {
        [self setBackViewStatus:Hidden];
    }
}
- (void)requestFreeAppOrGameFail:(int)page type:(NSString*)type userData:(id)userData{
    NSString *typeNumber = [NSString stringWithFormat:@"%d",[[userData objectForKey:@"listType"] integerValue]];
    int count = [[identifier componentsSeparatedByString:typeNumber] count];
    if (count<=1) return;
    
    // 下拉刷新请求失败
    if ([[userData objectForKey:@"isEGORefreshResult"] boolValue]) {
        [self showDownRefreshFailedLabel];
        return;
    }
    
    //
    if (page==1){
        [self setBackViewStatus:Failed];
        return ;
    }
    
    // 上拉刷新失败
    hasReceivedFailedFlag = YES;
    if (scrollEndFlag) {
        [self setUpPullRefreshFailedView];
    }
}

#pragma mark - HotApp(最热应用)

-(void)requestHotAppList
{ // HotApp(最热应用)
    [[MarketServerManage getManager] getAppColumnHotAllList:pageNumber userData:identifier];
}

-(void)appColumnHotAllListRequestSucess:(NSDictionary *)dataDic pageCount:(int)pageCount userData:(id)userData
{
    if (![userData isEqual:identifier] && ![userData isEqual:identifier_NoCache]) return;
    //
    if (![self checkListData:dataDic] && ![self checkFlag:dataDic]) {
        [self appColumnHotAllListRequestFail:pageCount userData:userData];
//        NSLog(@"hotApp失败");
        return;
    }
    
    [self setListDataSource:dataDic userData:userData];
    
    // 第一次
    if (pageCount == 1) {
        [self setBackViewStatus:Hidden];
    }
    
}

-(void)appColumnHotAllListRequestFail:(int)pageCount userData:(id)userData
{
    [self execFailedOpearation:pageCount userData:userData];
}

#pragma mark - LatestApp(最新应用)

-(void)requestLatestAppList
{ // LatestApp(最新应用)
    [[MarketServerManage getManager] getAppColumnNewAllList:pageNumber userData:identifier];
}

-(void)appColumnNewAllListRequestSucess:(NSDictionary *)dataDic pageCount:(int)pageCount userData:(id)userData
{
    if (![userData isEqual:identifier] && ![userData isEqual:identifier_NoCache]) return;
    //
    if (![self checkListData:dataDic] && ![self checkFlag:dataDic]) {
        [self appColumnNewAllListRequestFail:pageCount userData:userData];
//        NSLog(@"latestApp失败");
        return;
    }
    
    [self setListDataSource:dataDic userData:userData];
    
    // 第一次
    if (pageCount == 1) {
        [self setBackViewStatus:Hidden];
    }
}

-(void)appColumnNewAllListRequestFail:(int)pageCount userData:(id)userData
{
    [self execFailedOpearation:pageCount userData:userData];
}

#pragma mark - RankingListApp(应用周、月、总排行榜)

-(void)requestAppRankingList:(MarketListType)rankingListType
{ // RankingListApp(应用周、月、总排行榜)
    switch (rankingListType) {
        case marketList_AppWeekRankingType:
            [[MarketServerManage getManager] getAppRankingListColumn:WEEK_RANKING_LIST pageCount:pageNumber userData:identifier];
            break;
        case marketList_AppMonthRankingType:
            [[MarketServerManage getManager] getAppRankingListColumn:MONTH_RANKING_LIST pageCount:pageNumber userData:identifier];
            break;
        case marketList_AppTotalRankingType:
            [[MarketServerManage getManager] getAppRankingListColumn:TOTAL_RANKING_LIST pageCount:pageNumber userData:identifier];
            break;
            
        default:
            break;
    }
}

-(void)appRankingListColumnRequestSucess:(NSDictionary *)dataDic rankingList:(NSString *)rankingList pageCount:(int)pageCount userData:(id)userData
{ // 可以不区分是周、月、总排行榜
    if (![userData isEqual:identifier] && ![userData isEqual:identifier_NoCache]) return;
    //
    if (![self checkListData:dataDic] && ![self checkFlag:dataDic]) {
        [self appRankingListColumnRequestFail:rankingList pageCount:pageCount userData:userData];
//        NSLog(@"appRankingList失败");
        return;
    }
    
    [self setListDataSource:dataDic userData:userData];
    
    // 第一次
    if (pageCount == 1) {
        [self setBackViewStatus:Hidden];
    }
}

-(void)appRankingListColumnRequestFail:(NSString *)rankingList pageCount:(int)pageCount userData:(id)userData
{
    [self execFailedOpearation:pageCount userData:userData];
}

#pragma mark - HotGame(最热游戏)

-(void)requestHotGameList
{ // HotGame(最热游戏)
    [[MarketServerManage getManager] getGameColumnHotAllList:pageNumber userData:identifier];
}

-(void)gameColumnHotAllListRequestSucess:(NSDictionary *)dataDic pageCount:(int)pageCount userData:(id)userData
{
    if (![userData isEqual:identifier] && ![userData isEqual:identifier_NoCache]) return;
    //
    if (![self checkListData:dataDic] && ![self checkFlag:dataDic]) {
        [self gameColumnHotAllListRequestFail:pageCount userData:userData];
//        NSLog(@"hotGame失败");
        return;
    }
    
    [self setListDataSource:dataDic userData:userData];
    
    // 第一次
    if (pageCount == 1) {
        [self setBackViewStatus:Hidden];
    }
}

-(void)gameColumnHotAllListRequestFail:(int)pageCount userData:(id)userData
{
    [self execFailedOpearation:pageCount userData:userData];
}

#pragma mark - LatestGame(最新游戏)

-(void)requestLatestGameList
{ // LatestGame(最新游戏)
    [[MarketServerManage getManager] getGameColumnNewAllList:pageNumber userData:identifier];
}

-(void)gameColumnNewAllListRequestSucess:(NSDictionary *)dataDic pageCount:(int)pageCount userData:(id)userData
{
    if (![userData isEqual:identifier] && ![userData isEqual:identifier_NoCache]) return;
    //
    if (![self checkListData:dataDic] && ![self checkFlag:dataDic]) {
        [self gameColumnNewAllListRequestFail:pageCount userData:userData];
//        NSLog(@"latestGame失败");
        return;
    }
    
    [self setListDataSource:dataDic userData:userData];
    
    // 第一次
    if (pageCount == 1) {
        [self setBackViewStatus:Hidden];
    }
}

-(void)gameColumnNewAllListRequestFail:(int)pageCount userData:(id)userData
{
    [self execFailedOpearation:pageCount userData:userData];
}

#pragma mark - FengCeGame(封测游戏)

-(void)requestFengCeGameList
{ // FengCeGame(封测游戏)
    [[MarketServerManage getManager] getGameColumnFengCeBetaGameAllList:pageNumber userData:identifier];
}

-(void)gameColumnFengCeBetaGameAllListRequestSucess:(NSDictionary *)dataDic pageCount:(int)pageCount userData:(id)userData
{
    if (![userData isEqual:identifier] && ![userData isEqual:identifier_NoCache]) return;
    //
    if (![self checkListData:dataDic] && ![self checkFlag:dataDic]) {
        [self gameColumnFengCeBetaGameAllListRequestFail:pageCount userData:userData];
//        NSLog(@"fengCeGame失败");
        return;
    }
    
    [self setListDataSource:dataDic userData:userData];
    
    // 第一次
    if (pageCount == 1) {
        [self setBackViewStatus:Hidden];
    }
}

-(void)gameColumnFengCeBetaGameAllListRequestFail:(int)pageCount userData:(id)userData
{
    [self execFailedOpearation:pageCount userData:userData];
}

#pragma mark - RankingListGame(游戏周、月、总排行榜)

-(void)requestGameRankingList:(MarketListType)rankingListType
{ // RankingListGame(游戏周、月、总排行榜)
    switch (rankingListType) {
        case marketList_GameWeekRankingType:
            [[MarketServerManage getManager] getGameRankingListColumn:WEEK_RANKING_LIST pageCount:pageNumber userData:identifier];
            break;
        case marketList_GameMonthRankingType:
            [[MarketServerManage getManager] getGameRankingListColumn:MONTH_RANKING_LIST pageCount:pageNumber userData:identifier];
            break;
        case marketList_GameTotalRankingType:
            [[MarketServerManage getManager] getGameRankingListColumn:TOTAL_RANKING_LIST pageCount:pageNumber userData:identifier];
            break;
            
        default:
            break;
    }
}

-(void)gameRankingListColumnRequestSucess:(NSDictionary *)dataDic rankingList:(NSString *)rankingList pageCount:(int)pageCount userData:(id)userData
{
    if (![userData isEqual:identifier] && ![userData isEqual:identifier_NoCache]) return;
    //
    if (![self checkListData:dataDic] && ![self checkFlag:dataDic]) {
        [self gameRankingListColumnRequestFail:rankingList pageCount:pageCount userData:userData];
//        NSLog(@"RankingListGame失败");
        return;
    }
    
    [self setListDataSource:dataDic userData:userData];
    
    // 第一次
    if (pageCount == 1) {
        [self setBackViewStatus:Hidden];
    }
}

-(void)gameRankingListColumnRequestFail:(NSString *)rankingList pageCount:(int)pageCount userData:(id)userData
{
    [self execFailedOpearation:pageCount userData:userData];
}

@end
