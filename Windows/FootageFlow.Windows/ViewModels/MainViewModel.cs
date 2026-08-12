using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows;
using System.Windows.Data;
using System.Windows.Input;
using FootageFlow.Windows.Infrastructure;
using FootageFlow.Windows.Models;
using FootageFlow.Windows.Services;

namespace FootageFlow.Windows.ViewModels;

public sealed class MainViewModel : ObservableObject
{
    private readonly SettingsService _settings = new();
    private readonly WindowsSecureStore _credentials = new();
    private readonly CoreHostClient _core = new();
    private readonly YtDlpPlatformService _ytDlp = new();
    private readonly LocalizationService _localization;
    private CancellationTokenSource? _searchCancellation;
    private string _currentPage = "search";
    private string _query = "";
    private string _searchStatus = "";
    private bool _isSearching;
    private bool _isLoadingMore;
    private string _lastEffectiveQuery = "";
    private readonly Dictionary<string, ProviderContinuation> _continuations = new(StringComparer.OrdinalIgnoreCase);
    private string _mediaType = "video";
    private string _orientation = "all";
    private string _resolution = "all";
    private string _duration = "all";
    private string _licenseFilter = "all";
    private string _yearFrom = "";
    private string _yearTo = "";
    private bool _downloadableOnly;
    private int _selectedCount;
    private string _sort = "relevance";
    private ProjectRecord? _currentProject;
    private string _newProjectName = "";
    private string _projectEditName = "";
    private string _scriptText = "";
    private string _linkInput = "";
    private string _linkStatus = "";
    private bool _isLinkAnalyzing;
    private string _keywordSourceQuery = "";
    private string _clipboardSuggestion = "";
    private string _ignoredClipboardValue = "";
    private bool _isUpdateChecking;
    private string _updateStatusCode = "";

    public MainViewModel()
    {
        _localization = new LocalizationService(_settings);
        _localization.LanguageChanged += (_, _) => RefreshLanguage();
        Downloads = new DownloadQueueService(_core, _settings, _ytDlp, _localization);
        Downloads.DownloadCompleted += (_, _) => _ = LoadDatabaseAsync();
        ResultsView = CollectionViewSource.GetDefaultView(Results);
        ResultsView.Filter = value => value is MediaAsset asset && MatchesFilters(asset);
        ApplySort();
        FavoritesView = CollectionViewSource.GetDefaultView(Favorites);
        FavoritesView.Filter = value => value is SavedAssetRecord record && MatchesProject(record.ProjectID);
        HistoryView = CollectionViewSource.GetDefaultView(History);
        HistoryView.Filter = value => value is SearchHistoryRecord record && MatchesProject(record.ProjectID);
        DownloadRecordsView = CollectionViewSource.GetDefaultView(DownloadRecords);
        DownloadRecordsView.Filter = value => value is DownloadRecord record && MatchesProject(record.ProjectID);
        Providers = new ObservableCollection<ProviderOption>(new[]
        {
            NewProvider("pexels", "Pexels"), NewProvider("pixabay", "Pixabay"),
            NewProvider("wikimedia", "Wikimedia Commons"),
            NewProvider("internetArchive", "Internet Archive"), NewProvider("youtube", "YouTube"),
            NewProvider("nasa", "NASA"), NewProvider("libraryOfCongress", "Library of Congress"),
            NewProvider("nationalArchives", "National Archives"), NewProvider("europeana", "Europeana"),
            NewProvider("peertube", "PeerTube / SepiaSearch"), NewProvider("videvo", "Videvo"),
            NewProvider("videezy", "Videezy"), NewProvider("mixkit", "Mixkit"),
            NewProvider("coverr", "Coverr"), NewProvider("vimeo", "Vimeo"),
            NewProvider("openverse", "Openverse"), NewProvider("dailymotion", "Dailymotion")
        });
        foreach (var provider in Providers)
            provider.PropertyChanged += (_, args) =>
            {
                if (args.PropertyName != nameof(ProviderOption.Enabled)) return;
                if (provider.Enabled) _settings.Current.EnabledProviders.Add(provider.Id);
                else _settings.Current.EnabledProviders.Remove(provider.Id);
                _settings.Save();
                ResultsView.Refresh();
            };
        NavigateCommand = new RelayCommand(page => CurrentPage = page?.ToString() ?? "search");
        SearchCommand = new AsyncRelayCommand(_ => SearchAsync(), _ => !IsSearching);
        AddSearchKeywordCommand = new RelayCommand(_ => SearchKeywords.Add(new SearchKeyword
            { Id = Guid.NewGuid(), Text = "", IsEnabled = true }));
        RemoveSearchKeywordCommand = new RelayCommand(value =>
        {
            if (value is SearchKeyword keyword) SearchKeywords.Remove(keyword);
        });
        RegenerateKeywordsCommand = new AsyncRelayCommand(_ => RegenerateKeywordsAsync());
        LoadMoreCommand = new AsyncRelayCommand(_ => LoadMoreAsync(), _ => CanLoadMore && !IsSearching && !IsLoadingMore);
        StopSearchCommand = new RelayCommand(_ => _searchCancellation?.Cancel(), _ => IsSearching);
        OpenSourceCommand = new RelayCommand(asset => ShellService.OpenUrl((asset as MediaAsset)?.SourcePageURL));
        PreviewCommand = new RelayCommand(asset => PreviewRequested?.Invoke(asset as MediaAsset));
        FavoriteCommand = new AsyncRelayCommand(asset => ToggleFavoriteAsync(asset as MediaAsset));
        DownloadCommand = new RelayCommand(asset => EnqueueDownload(asset as MediaAsset));
        DownloadEditingCompatibleCommand = new RelayCommand(asset =>
            EnqueueDownload(WithEditingOutput(asset as MediaAsset, "editingCompatibleMP4")));
        DownloadAudioOnlyCommand = new RelayCommand(asset =>
            EnqueueDownload(WithEditingOutput(asset as MediaAsset, "audioOnly")));
        SelectAllVisibleCommand = new RelayCommand(_ => SelectAllVisible());
        ClearSelectionCommand = new RelayCommand(_ => ClearSelection());
        DownloadSelectedCommand = new RelayCommand(_ => DownloadSelected());
        AddSelectedToProjectCommand = new AsyncRelayCommand(_ => AddSelectedToProjectAsync(),
            _ => CurrentProject is not null && SelectedCount > 0);
        CreateProjectFromSelectionCommand = new AsyncRelayCommand(_ => CreateProjectFromSelectionAsync());
        CopySelectedSourceCommand = new AsyncRelayCommand(_ => CopySelectedSourcesAsync());
        CopySourceCommand = new AsyncRelayCommand(asset => CopyTextAsync(asset as MediaAsset, "formatSource"));
        CopyAttributionCommand = new AsyncRelayCommand(asset => CopyTextAsync(asset as MediaAsset, "formatAttribution"));
        CreateProjectCommand = new AsyncRelayCommand(_ => CreateProjectAsync());
        ClearProjectCommand = new RelayCommand(_ => CurrentProject = null);
        SaveProjectCommand = new AsyncRelayCommand(_ => SaveProjectAsync(), _ => CurrentProject is not null);
        DeleteProjectCommand = new AsyncRelayCommand(project => DeleteProjectAsync(project as ProjectRecord));
        SearchHistoryCommand = new AsyncRelayCommand(history => SearchHistoryAsync(history as SearchHistoryRecord));
        DeleteHistoryCommand = new AsyncRelayCommand(history => DeleteHistoryAsync(history as SearchHistoryRecord));
        ClearHistoryCommand = new AsyncRelayCommand(_ => ClearHistoryAsync());
        CancelDownloadCommand = new RelayCommand(item => Downloads.Cancel((DownloadTaskItem)item!));
        RetryDownloadCommand = new RelayCommand(item => Downloads.Retry((DownloadTaskItem)item!));
        RetryFailedDownloadsCommand = new RelayCommand(_ => Downloads.RetryFailed());
        RevealDownloadCommand = new RelayCommand(item =>
        {
            if ((item as DownloadTaskItem)?.LocalPath is { } path) ShellService.Reveal(path);
        });
        RevealRecordCommand = new RelayCommand(record =>
        {
            if ((record as DownloadRecord)?.LocalPath is { } path) ShellService.Reveal(path);
        });
        OpenRecordCommand = new RelayCommand(record =>
        {
            if ((record as DownloadRecord)?.LocalPath is { } path) ShellService.OpenFile(path);
        });
        OpenRecordSourceCommand = new RelayCommand(record =>
            ShellService.OpenUrl((record as DownloadRecord)?.SourcePageURL));
        RemoveDownloadRecordCommand = new AsyncRelayCommand(record => RemoveDownloadRecordAsync(record as DownloadRecord));
        AnalyzeScriptCommand = new AsyncRelayCommand(_ => AnalyzeScriptAsync());
        PasteLinkCommand = new RelayCommand(_ => LinkInput = Clipboard.ContainsText() ? Clipboard.GetText() : "");
        AnalyzeLinksCommand = new AsyncRelayCommand(_ => AnalyzeLinksAsync(), _ => !IsLinkAnalyzing);
        DownloadLinkSelectedCommand = new RelayCommand(_ => DownloadLinkSelected());
        OpenLinkOriginalCommand = new RelayCommand(item =>
            ShellService.OpenUrl((item as LinkDownloadItem)?.Analysis?.OriginalURL));
        ResetClipCommand = new RelayCommand(value =>
        {
            if (value is not LinkDownloadItem item) return;
            item.ClipStart = "00:00:00";
            item.InitializeClipEnd();
        });
        AnalyzeClipboardCommand = new AsyncRelayCommand(_ => AnalyzeClipboardAsync());
        IgnoreClipboardCommand = new RelayCommand(_ => IgnoreClipboard());
        DisableClipboardCommand = new RelayCommand(_ =>
        {
            ClipboardDetectionEnabled = false;
            IgnoreClipboard();
        });
        OpenFeedbackCommand = new AsyncRelayCommand(value => OpenFeedbackAsync(value?.ToString()));
        CheckForUpdatesCommand = new AsyncRelayCommand(_ => CheckForUpdatesAsync(manual: true), _ => !IsUpdateChecking);
        RefreshProviderModes();
        SearchStatus = T("search.initialStatus");
        _ = LoadDatabaseAsync();
    }

    public event Action<MediaAsset?>? PreviewRequested;
    public event Action<AppReleaseInfo>? UpdateAvailable;
    public DownloadQueueService Downloads { get; }
    public ObservableCollection<ProviderOption> Providers { get; }
    public ObservableCollection<MediaAsset> Results { get; } = [];
    public ICollectionView ResultsView { get; }
    public ObservableCollection<SearchKeyword> SearchKeywords { get; } = [];
    public ObservableCollection<ProjectRecord> Projects { get; } = [];
    public ObservableCollection<SavedAssetRecord> Favorites { get; } = [];
    public ObservableCollection<SearchHistoryRecord> History { get; } = [];
    public ObservableCollection<DownloadRecord> DownloadRecords { get; } = [];
    public ICollectionView FavoritesView { get; }
    public ICollectionView HistoryView { get; }
    public ICollectionView DownloadRecordsView { get; }
    public ObservableCollection<string> ScriptSegments { get; } = [];
    public ObservableCollection<LinkDownloadItem> LinkItems { get; } = [];

    public ICommand NavigateCommand { get; }
    public ICommand SearchCommand { get; }
    public ICommand AddSearchKeywordCommand { get; }
    public ICommand RemoveSearchKeywordCommand { get; }
    public ICommand RegenerateKeywordsCommand { get; }
    public ICommand LoadMoreCommand { get; }
    public ICommand StopSearchCommand { get; }
    public ICommand OpenSourceCommand { get; }
    public ICommand PreviewCommand { get; }
    public ICommand FavoriteCommand { get; }
    public ICommand DownloadCommand { get; }
    public ICommand DownloadEditingCompatibleCommand { get; }
    public ICommand DownloadAudioOnlyCommand { get; }
    public ICommand SelectAllVisibleCommand { get; }
    public ICommand ClearSelectionCommand { get; }
    public ICommand DownloadSelectedCommand { get; }
    public ICommand AddSelectedToProjectCommand { get; }
    public ICommand CreateProjectFromSelectionCommand { get; }
    public ICommand CopySelectedSourceCommand { get; }
    public ICommand CopySourceCommand { get; }
    public ICommand CopyAttributionCommand { get; }
    public ICommand CreateProjectCommand { get; }
    public ICommand ClearProjectCommand { get; }
    public ICommand SaveProjectCommand { get; }
    public ICommand DeleteProjectCommand { get; }
    public ICommand SearchHistoryCommand { get; }
    public ICommand DeleteHistoryCommand { get; }
    public ICommand ClearHistoryCommand { get; }
    public ICommand CancelDownloadCommand { get; }
    public ICommand RetryDownloadCommand { get; }
    public ICommand RetryFailedDownloadsCommand { get; }
    public ICommand RevealDownloadCommand { get; }
    public ICommand RevealRecordCommand { get; }
    public ICommand OpenRecordCommand { get; }
    public ICommand OpenRecordSourceCommand { get; }
    public ICommand RemoveDownloadRecordCommand { get; }
    public ICommand AnalyzeScriptCommand { get; }
    public ICommand PasteLinkCommand { get; }
    public ICommand AnalyzeLinksCommand { get; }
    public ICommand DownloadLinkSelectedCommand { get; }
    public ICommand OpenLinkOriginalCommand { get; }
    public ICommand ResetClipCommand { get; }
    public ICommand AnalyzeClipboardCommand { get; }
    public ICommand IgnoreClipboardCommand { get; }
    public ICommand DisableClipboardCommand { get; }
    public ICommand OpenFeedbackCommand { get; }
    public ICommand CheckForUpdatesCommand { get; }

    public string CurrentPage
    {
        get => _currentPage;
        set
        {
            if (!Set(ref _currentPage, value)) return;
            OnPropertyChanged(nameof(IsSearchPage)); OnPropertyChanged(nameof(IsScriptPage));
            OnPropertyChanged(nameof(IsProjectsPage)); OnPropertyChanged(nameof(IsFavoritesPage));
            OnPropertyChanged(nameof(IsDownloadsPage)); OnPropertyChanged(nameof(IsHistoryPage));
            OnPropertyChanged(nameof(IsSettingsPage));
            OnPropertyChanged(nameof(IsLinkDownloaderPage));
            OnPropertyChanged(nameof(IsFeedbackPage));
        }
    }
    public bool IsSearchPage => CurrentPage == "search";
    public bool IsScriptPage => CurrentPage == "script";
    public bool IsProjectsPage => CurrentPage == "projects";
    public bool IsFavoritesPage => CurrentPage == "favorites";
    public bool IsDownloadsPage => CurrentPage == "downloads";
    public bool IsHistoryPage => CurrentPage == "history";
    public bool IsSettingsPage => CurrentPage == "settings";
    public bool IsLinkDownloaderPage => CurrentPage == "linkDownloader";
    public bool IsFeedbackPage => CurrentPage == "feedback";
    public string Query { get => _query; set => Set(ref _query, value); }
    public string SearchStatus { get => _searchStatus; set => Set(ref _searchStatus, value); }
    public bool IsSearching
    {
        get => _isSearching;
        private set
        {
            if (!Set(ref _isSearching, value)) return;
            (SearchCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
            (StopSearchCommand as RelayCommand)?.RaiseCanExecuteChanged();
            (LoadMoreCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
        }
    }
    public bool IsLoadingMore
    {
        get => _isLoadingMore;
        private set
        {
            if (!Set(ref _isLoadingMore, value)) return;
            OnPropertyChanged(nameof(CanLoadMore));
            (LoadMoreCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
        }
    }
    public bool CanLoadMore => _continuations.Count > 0;
    public string MediaType { get => _mediaType; set { if (Set(ref _mediaType, value)) ResultsView.Refresh(); } }
    public string Orientation { get => _orientation; set { if (Set(ref _orientation, value)) ResultsView.Refresh(); } }
    public string Resolution { get => _resolution; set { if (Set(ref _resolution, value)) ResultsView.Refresh(); } }
    public string Duration { get => _duration; set { if (Set(ref _duration, value)) ResultsView.Refresh(); } }
    public string LicenseFilter { get => _licenseFilter; set { if (Set(ref _licenseFilter, value)) ResultsView.Refresh(); } }
    public string YearFrom { get => _yearFrom; set { if (Set(ref _yearFrom, Digits(value))) ResultsView.Refresh(); } }
    public string YearTo { get => _yearTo; set { if (Set(ref _yearTo, Digits(value))) ResultsView.Refresh(); } }
    public bool DownloadableOnly { get => _downloadableOnly; set { if (Set(ref _downloadableOnly, value)) ResultsView.Refresh(); } }
    public bool SmartExpansionEnabled
    {
        get => _settings.Current.SmartSearchExpansionEnabled;
        set
        {
            if (_settings.Current.SmartSearchExpansionEnabled == value) return;
            _settings.Current.SmartSearchExpansionEnabled = value;
            _settings.Save();
            OnPropertyChanged();
            _keywordSourceQuery = "";
        }
    }
    public bool ClipboardDetectionEnabled
    {
        get => _settings.Current.ClipboardMediaLinkDetectionEnabled;
        set
        {
            if (_settings.Current.ClipboardMediaLinkDetectionEnabled == value) return;
            _settings.Current.ClipboardMediaLinkDetectionEnabled = value;
            _settings.Save();
            OnPropertyChanged();
            if (!value) IgnoreClipboard();
        }
    }
    public bool HasClipboardSuggestion => !string.IsNullOrWhiteSpace(_clipboardSuggestion);
    public int ClipboardSuggestionCount => MediaLinkLines(_clipboardSuggestion).Count;
    public string ClipboardSuggestionText => ClipboardSuggestionCount == 1
        ? T("clipboard.mediaLinkDetected") : _localization.Text("clipboard.mediaLinksDetected", ClipboardSuggestionCount);
    public int SelectedCount
    {
        get => _selectedCount;
        private set
        {
            if (!Set(ref _selectedCount, value)) return;
            OnPropertyChanged(nameof(HasSelection));
            OnPropertyChanged(nameof(SelectionStatus));
            (AddSelectedToProjectCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
        }
    }
    public bool HasSelection => SelectedCount > 0;
    public string Sort
    {
        get => _sort;
        set
        {
            if (!Set(ref _sort, value)) return;
            ApplySort();
        }
    }
    public ProjectRecord? CurrentProject
    {
        get => _currentProject;
        set
        {
            if (!Set(ref _currentProject, value)) return;
            ProjectEditName = value?.Name ?? "";
            ScriptText = value?.Script ?? "";
            (SaveProjectCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
            (AddSelectedToProjectCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
            FavoritesView.Refresh();
            HistoryView.Refresh();
            DownloadRecordsView.Refresh();
        }
    }
    public string NewProjectName { get => _newProjectName; set => Set(ref _newProjectName, value); }
    public string ProjectEditName { get => _projectEditName; set => Set(ref _projectEditName, value); }
    public string ScriptText { get => _scriptText; set => Set(ref _scriptText, value); }
    public string LinkInput
    {
        get => _linkInput;
        set
        {
            if (!Set(ref _linkInput, value)) return;
            OnPropertyChanged(nameof(LinkDetectedText));
            OnPropertyChanged(nameof(LinkAnalyzeText));
        }
    }
    public string LinkStatus { get => _linkStatus; set => Set(ref _linkStatus, value); }
    public bool IsLinkAnalyzing
    {
        get => _isLinkAnalyzing;
        private set
        {
            if (!Set(ref _isLinkAnalyzing, value)) return;
            (AnalyzeLinksCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
        }
    }
    public string DownloadRoot => _settings.Current.DownloadRoot;
    public string LanguageCode => _localization.Language;
    public string LanguageButton => $"🌐 {_localization.DisplayName}";
    public string CurrentVersion
    {
        get
        {
            var version = typeof(MainViewModel).Assembly.GetName().Version;
            return version is null ? "0.7.0" : $"{version.Major}.{version.Minor}.{Math.Max(0, version.Build)}";
        }
    }
    public bool IsUpdateChecking
    {
        get => _isUpdateChecking;
        private set
        {
            if (!Set(ref _isUpdateChecking, value)) return;
            (CheckForUpdatesCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
        }
    }
    public string UpdateStatus => _updateStatusCode switch
    {
        "checking" => T("update.checking"),
        "upToDate" => T("update.upToDate"),
        "noNetwork" => T("update.noNetwork"),
        "timeout" => T("update.timeout"),
        "rateLimited" => T("update.rateLimited"),
        "failed" => T("update.checkFailed"),
        _ => ""
    };

    public string T(string key) => _localization.Text(key);
    public string NavSearch => T("nav.quickSearch");
    public string NavScript => T("nav.scriptSearch");
    public string NavLinkDownloader => T("nav.linkDownloader");
    public string NavProjects => T("nav.projects");
    public string NavFavorites => T("nav.favorites");
    public string NavDownloads => T("nav.downloads");
    public string NavHistory => T("search.history");
    public string NavSettings => T("nav.settings");
    public string NavFeedback => T("nav.feedback");
    public string SearchTagline => T("search.tagline");
    public string SearchPlaceholder => T("search.placeholder");
    public string SearchApiRecommendation => T("search.apiRecommendation");
    public string SearchButtonText => T("search.button");
    public string LoadMoreText => T("search.loadMore");
    public string LoadingMoreText => T("search.loadingMore");
    public string StopText => T("common.stop");
    public string KeywordsTitle => T("search.currentKeywords");
    public string SmartExpansionText => T("search.smartExpansion");
    public string AddKeywordText => T("search.addKeyword");
    public string RegenerateKeywordsText => T("search.regenerateKeywords");
    public string TypeTitle => T("filter.type");
    public string OrientationTitle => T("filter.orientation");
    public string ResolutionTitle => T("filter.resolution");
    public string DurationTitle => T("filter.duration");
    public string LicenseTitle => T("filter.license");
    public string SortTitle => T("filter.sort");
    public string ProjectTitle => T("common.project");
    public string ProjectAllText => T("project.all");
    public string ScriptTitle => T("script.title");
    public string ScriptHelp => T("script.help");
    public string ScriptAnalyze => T("script.analyze");
    public string ProjectsTitle => T("project.title");
    public string NewProjectTitle => T("project.new");
    public string FavoritesTitle => T("nav.favorites");
    public string DownloadsTitle => T("download.title");
    public string HistoryTitle => T("search.history");
    public string SettingsTitle => T("nav.settings");
    public string SourcesTitle => T("settings.sourcesProviders");
    public string ApiExplanation => T("settings.optionalAPIExplanation");
    public string PrivacyTitle => T("settings.privacy");
    public string PrivacyBody => T("settings.privacyBody");
    public string PreviewText => T("media.preview");
    public string ThumbnailUnavailableText => T("media.thumbnailUnavailable");
    public string RetryThumbnailText => T("media.retryThumbnail");
    public string FavoriteText => T("media.favorite");
    public string DownloadText => T("media.download");
    public string EditingCompatibleOutputText => T("link.output.editingCompatibleMP4");
    public string AudioOnlyOutputText => T("link.output.audioOnly");
    public string OpenSourceText => T("media.openSource");
    public string AllText => T("common.all");
    public string VideoText => T("common.video");
    public string ImageText => T("common.image");
    public string AudioText => T("common.audio");
    public string LandscapeText => T("media.landscape");
    public string PortraitText => T("media.portrait");
    public string SquareText => T("media.square");
    public string UnderMinuteText => T("filter.underMinute");
    public string OneToFiveText => T("filter.oneToFive");
    public string FiveToTwentyText => T("filter.fiveToTwenty");
    public string OverTwentyText => T("filter.overTwenty");
    public string LicenseKnownText => T("license.knownOnly");
    public string LicenseOpenText => T("license.openlyLicensed");
    public string LicensePublicDomainText => T("license.publicDomain");
    public string LicenseUnknownText => T("license.unknown");
    public string LicenseSafeText => T("license.safe");
    public string LicenseAttributionText => T("license.attribution");
    public string LicenseRestrictedText => T("license.restricted");
    public string SortRelevanceText => T("sort.relevance");
    public string SortNewestText => T("sort.newest");
    public string SortResolutionText => T("sort.resolution");
    public string SortDurationText => T("sort.duration");
    public string DeleteText => T("common.delete");
    public string CancelText => T("common.cancel");
    public string RetryText => T("common.retry");
    public string RetryFailedText => T("download.retryFailed");
    public string OpenFolderText => T("download.openFolder");
    public string OpenFileText => T("download.openFile");
    public string ClearHistoryText => T("history.clear");
    public string SearchAgainText => T("history.research");
    public string SaveText => T("common.save");
    public string RemoveKeyText => T("settings.removeAPIKey");
    public string TestConnectionText => T("settings.testConnection");
    public string DownloadFolderText => T("settings.downloadRoot");
    public string ChooseText => T("settings.choose");
    public string DownloadableOnlyText => T("filter.downloadableOnly");
    public string YearFromText => T("filter.yearFrom");
    public string YearToText => T("filter.yearTo");
    public string SelectAllVisibleText => T("selection.selectAllVisible");
    public string DownloadSelectedText => T("selection.downloadSelected");
    public string AddToProjectText => T("selection.addToProject");
    public string CopySourceInfoText => T("selection.copySourceInfo");
    public string ClearSelectionText => T("selection.clear");
    public string CopySourceText => T("media.copySource");
    public string CopyAttributionText => T("media.copyAttribution");
    public string SelectionStatus => _localization.Text("selection.count", SelectedCount);
    public string OpenOfficialSearchText => T("provider.openOfficialSearch");
    public string LinkTagline => T("link.tagline");
    public string LinkPasteText => T("link.paste");
    public string LinkAnalyzeText => LinkURLLines().Count > 1 ? T("link.analyzeAll") : T("link.analyze");
    public string LinkDownloadSelectedText => T("link.downloadSelected");
    public string LinkDetectedText => _localization.Text("link.detectedCount", LinkURLLines().Count);
    public string LinkQualityText => T("link.quality");
    public string LinkSubtitlesText => T("link.subtitles");
    public string LinkOpenOriginalText => T("link.openOriginal");
    public string LinkLegalNotice => T("link.legalNotice");
    public string LinkFormatsText => T("link.formatsCount");
    public string LinkDownloadModeText => T("link.downloadMode");
    public string LinkOutputFormatText => T("link.outputFormat");
    public string LinkClipStartText => T("link.clip.start");
    public string LinkClipEndText => T("link.clip.end");
    public string ResetText => T("common.reset");
    public string ClipboardSettingText => T("clipboard.setting");
    public string ClipboardPrivacyDetail => T("clipboard.privacyDetail");
    public string ClipboardIgnoreText => T("clipboard.ignore");
    public string ClipboardDisableText => T("clipboard.disable");
    public string FeedbackIntro => T("feedback.intro");
    public string FeedbackReportBug => T("feedback.reportBug");
    public string FeedbackSuggestFeature => T("feedback.suggestFeature");
    public string FeedbackAskQuestion => T("feedback.askQuestion");
    public string FeedbackViewGitHub => T("feedback.viewGitHub");
    public string FeedbackViewReleases => T("feedback.viewReleases");
    public string FeedbackStarPrompt => T("feedback.starPrompt");
    public string FeedbackStarButton => $"⭐ {T("feedback.viewGitHub")}";
    public string FeedbackPrivacy => T("feedback.privacy");
    public string UpdateSettingsTitle => T("update.settingsTitle");
    public string UpdateSettingsDetail => T("update.settingsDetail");
    public string UpdateCurrentVersionLabel => T("update.currentVersion");
    public string UpdateCheckNowText => T("update.checkNow");

    public void SetLanguage(string language) => _localization.SetLanguage(language);

    public Task CheckForUpdatesOnLaunchAsync() => CheckForUpdatesAsync(manual: false);

    public void RemindLater(AppReleaseInfo release)
    {
        _settings.Current.DeferredUpdateVersion = release.Version;
        _settings.Current.DeferredUpdateUntil = DateTimeOffset.UtcNow.AddHours(24);
        _settings.Save();
    }

    public void ViewUpdate(AppReleaseInfo release)
    {
        RemindLater(release);
        ShellService.OpenUrl(release.PageURL);
    }

    private async Task CheckForUpdatesAsync(bool manual)
    {
        if (IsUpdateChecking) return;
        IsUpdateChecking = true;
        if (manual) SetUpdateStatus("checking");
        try
        {
            var response = await _core.SendAsync(new CoreRequest
            {
                Action = "checkUpdate", Language = _settings.Current.Language,
                DeferredUpdateVersion = _settings.Current.DeferredUpdateVersion,
                DeferredUpdateUntil = _settings.Current.DeferredUpdateUntil,
                ForceUpdatePrompt = manual
            }, timeout: TimeSpan.FromSeconds(20));
            if (!response.Success)
            {
                if (manual) SetUpdateStatus(response.ErrorCode switch
                {
                    "noNetwork" => "noNetwork", "timeout" => "timeout",
                    "rateLimited" => "rateLimited", _ => "failed"
                });
                return;
            }
            if (response.UpdateStatus == "available" && response.Release is { } release)
            {
                if (manual) SetUpdateStatus("");
                UpdateAvailable?.Invoke(release);
            }
            else if (manual) SetUpdateStatus("upToDate");
        }
        catch (CoreHostException error)
        {
            if (manual) SetUpdateStatus(error.Code == "timeout" ? "timeout" : "failed");
        }
        catch
        {
            if (manual) SetUpdateStatus("failed");
        }
        finally { IsUpdateChecking = false; }
    }

    private void SetUpdateStatus(string value)
    {
        _updateStatusCode = value;
        OnPropertyChanged(nameof(UpdateStatus));
    }

    public void CheckClipboardCandidate(string text)
    {
        if (!ClipboardDetectionEnabled || !IsLinkDownloaderPage || string.IsNullOrWhiteSpace(text) ||
            string.Equals(text, _ignoredClipboardValue, StringComparison.Ordinal)) return;
        var links = MediaLinkLines(text);
        if (links.Count == 0) return;
        var existing = LinkURLLines().ToHashSet(StringComparer.OrdinalIgnoreCase);
        var fresh = links.Where(value => !existing.Contains(value)).ToArray();
        if (fresh.Length == 0) return;
        _clipboardSuggestion = string.Join(Environment.NewLine, fresh);
        OnPropertyChanged(nameof(HasClipboardSuggestion)); OnPropertyChanged(nameof(ClipboardSuggestionCount));
        OnPropertyChanged(nameof(ClipboardSuggestionText));
    }

    private async Task AnalyzeClipboardAsync()
    {
        if (!HasClipboardSuggestion) return;
        LinkInput = _clipboardSuggestion;
        _ignoredClipboardValue = _clipboardSuggestion;
        _clipboardSuggestion = "";
        OnPropertyChanged(nameof(HasClipboardSuggestion));
        await AnalyzeLinksAsync();
    }

    private void IgnoreClipboard()
    {
        _ignoredClipboardValue = _clipboardSuggestion;
        _clipboardSuggestion = "";
        OnPropertyChanged(nameof(HasClipboardSuggestion)); OnPropertyChanged(nameof(ClipboardSuggestionCount));
        OnPropertyChanged(nameof(ClipboardSuggestionText));
    }

    private static List<string> MediaLinkLines(string text)
    {
        string[] hosts = ["youtube.com", "youtu.be", "x.com", "twitter.com", "vimeo.com",
            "dailymotion.com", "tiktok.com", "twitch.tv", "reddit.com", "soundcloud.com",
            "facebook.com", "instagram.com"];
        string[] extensions = [".mp4", ".mov", ".m4v", ".webm", ".mp3", ".m4a", ".wav", ".ogg"];
        return text.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries).Select(value => value.Trim())
            .Where(value => LinkUrlSafety.TryCreate(value, out var uri) &&
                (hosts.Any(host => uri.Host.Equals(host, StringComparison.OrdinalIgnoreCase) ||
                    uri.Host.EndsWith("." + host, StringComparison.OrdinalIgnoreCase)) ||
                 extensions.Any(ext => uri.AbsolutePath.EndsWith(ext, StringComparison.OrdinalIgnoreCase))))
            .Distinct(StringComparer.OrdinalIgnoreCase).ToList();
    }

    public void OpenOfficialSearch(string provider)
    {
        var query = Uri.EscapeDataString(string.IsNullOrWhiteSpace(Query) ? "history" : Query.Trim());
        var url = provider switch
        {
            "nasa" => $"https://images.nasa.gov/search?q={query}",
            "libraryOfCongress" => $"https://www.loc.gov/film-and-videos/?q={query}",
            "nationalArchives" => $"https://catalog.archives.gov/search?q={query}",
            "europeana" => $"https://www.europeana.eu/en/search?query={query}",
            "peertube" => $"https://sepiasearch.org/search?search={query}",
            "videvo" => $"https://www.videvo.net/stock-video-footage/{query}/",
            "videezy" => $"https://www.videezy.com/free-video/{query}",
            "mixkit" => $"https://mixkit.co/free-stock-video/?q={query}",
            "coverr" => $"https://coverr.co/stock-video-footage?query={query}",
            "vimeo" => $"https://vimeo.com/search?q={query}",
            "dailymotion" => $"https://www.dailymotion.com/search/{query}/videos",
            _ => null
        };
        ShellService.OpenUrl(url);
    }

    public void SaveApiKey(string provider, string value)
    {
        var clean = value.Trim();
        if (clean.Length == 0) return;
        _credentials.Save(provider, clean);
        RefreshProviderModes();
    }

    public void RemoveApiKey(string provider)
    {
        _credentials.Remove(provider);
        RefreshProviderModes();
    }

    public async Task<string> TestProviderAsync(string provider)
    {
        var option = Providers.First(x => x.Id == provider);
        option.Status = T("settings.connecting");
        try
        {
            if (provider == "youtube" && string.IsNullOrWhiteSpace(ReadCredential(provider)))
            {
                _ = await _ytDlp.SearchAsync("bank", 1, CancellationToken.None);
                option.Status = T("settings.connectionSuccess");
                return option.Status;
            }
            if (provider is "nationalArchives" or "europeana" or "videvo" or "videezy" or "mixkit" or "coverr" or "vimeo" &&
                string.IsNullOrWhiteSpace(ReadCredential(provider)))
            {
                option.Status = T("provider.limitedMode");
                return option.Status;
            }
            var response = await _core.SendAsync(new CoreRequest
            {
                Action = "providerTest", ProviderIDs = [provider],
                ApiKeys = CredentialDictionary(provider), Language = _settings.Current.Language
            });
            option.Status = response.Success ? T("settings.connectionSuccess") :
                response.ErrorMessage ?? T("settings.connectionFailed");
        }
        catch (Exception error) { option.Status = error.Message; }
        return option.Status;
    }

    public void ChooseDownloadRoot(string path)
    {
        if (string.IsNullOrWhiteSpace(path)) return;
        _settings.Current.DownloadRoot = path;
        _settings.Save();
        OnPropertyChanged(nameof(DownloadRoot));
    }

    private ProviderOption NewProvider(string id, string name) =>
        new(id, name, _settings.Current.EnabledProviders.Contains(id));

    private async Task SearchAsync()
    {
        var clean = Query.Trim();
        if (clean.Length == 0) { SearchStatus = T("search.enterQuery"); return; }
        _searchCancellation?.Cancel();
        _searchCancellation = new CancellationTokenSource();
        var cancellationToken = _searchCancellation.Token;
        IsSearching = true;
        Results.Clear(); SelectedCount = 0;
        _continuations.Clear();
        OnPropertyChanged(nameof(CanLoadMore));
        var selected = Providers.Where(x => x.Enabled).ToList();
        if (selected.Count == 0) { SearchStatus = T("search.noResults"); IsSearching = false; return; }
        SearchStatus = T("search.searchingOthers");
        try
        {
            if (!string.Equals(_keywordSourceQuery, clean, StringComparison.Ordinal) || SearchKeywords.Count == 0)
                await RegenerateKeywordsAsync(cancellationToken);
            var effectiveQueries = SearchKeywords.Where(x => x.IsEnabled && !string.IsNullOrWhiteSpace(x.Text))
                .Select(x => x.Text.Trim()).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
            if (effectiveQueries.Length == 0) effectiveQueries = [clean];
            _lastEffectiveQuery = effectiveQueries[0];
            var tasks = selected.ToDictionary(option => option.Id,
                option => SearchProviderExpandedAsync(option, effectiveQueries, cancellationToken));
            var pending = tasks.Values.ToList();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            while (pending.Count > 0)
            {
                var completed = await Task.WhenAny(pending);
                pending.Remove(completed);
                var batch = await completed;
                if (batch.Continuation is not null) _continuations[batch.Provider] = batch.Continuation;
                else _continuations.Remove(batch.Provider);
                foreach (var asset in batch.Assets)
                    if (seen.Add(asset.StableId))
                    {
                        asset.PropertyChanged += ResultPropertyChanged;
                        Results.Add(asset);
                    }
                SearchStatus = pending.Count > 0
                    ? $"{T("search.searchingOthers")}  {Results.Count}"
                    : _localization.Text("search.found", Results.Count);
                OnPropertyChanged(nameof(CanLoadMore));
                (LoadMoreCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
            }
            await _core.SendAsync(new CoreRequest
            {
                Action = "addHistory", Query = clean, Keywords = SearchKeywords.Select(x => x.Text).ToArray(),
                ProviderIDs = selected.Select(x => x.Id).ToArray(), ProjectID = CurrentProject?.Id.ToString(),
                ResultCount = Results.Count, Language = _settings.Current.Language
            }, cancellationToken: cancellationToken);
            await LoadDatabaseAsync();
        }
        catch (OperationCanceledException) { SearchStatus = T("search.stopped"); }
        catch (Exception error) { SearchStatus = error.Message; }
        finally { IsSearching = false; }
    }

    private async Task RegenerateKeywordsAsync(CancellationToken cancellationToken = default)
    {
        var clean = Query.Trim();
        if (clean.Length == 0) return;
        var keywords = await _core.SendAsync(new CoreRequest
        {
            Action = "keywords", Query = clean, SmartExpansion = SmartExpansionEnabled,
            Language = _settings.Current.Language
        }, cancellationToken: cancellationToken);
        SearchKeywords.Clear();
        foreach (var keyword in keywords.Keywords ?? []) SearchKeywords.Add(keyword);
        _keywordSourceQuery = clean;
    }

    private async Task<ProviderBatch> SearchProviderExpandedAsync(
        ProviderOption option, IReadOnlyList<string> queries, CancellationToken cancellationToken)
    {
        var budget = option.Id switch
        {
            "youtube" or "dailymotion" or "vimeo" or "peertube" => 2,
            "wikimedia" or "internetArchive" or "nasa" or "libraryOfCongress" or
                "nationalArchives" or "europeana" => 4,
            _ => 3
        };
        var selectedQueries = queries.Take(budget).ToArray();
        var assets = new List<MediaAsset>();
        ProviderBatch? primary = null;
        foreach (var query in selectedQueries)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var batch = await SearchProviderAsync(option, query, cancellationToken);
            primary ??= batch;
            assets.AddRange(batch.Assets);
            if (batch.State.Availability is "rateLimited" or "temporarilyBlocked") break;
        }
        var first = primary ?? new ProviderBatch
        {
            Provider = option.Id, DisplayName = option.DisplayName,
            State = new ProviderState { Availability = "unavailable" }
        };
        return new ProviderBatch
        {
            Provider = first.Provider, DisplayName = first.DisplayName, Mode = first.Mode,
            State = first.State, Continuation = first.Continuation, TotalResults = first.TotalResults,
            ErrorCode = first.ErrorCode,
            Assets = assets.GroupBy(value => value.StableId, StringComparer.OrdinalIgnoreCase)
                .Select(group => group.First()).ToArray()
        };
    }

    private async Task<ProviderBatch> SearchProviderAsync(
        ProviderOption option,
        string query,
        CancellationToken cancellationToken,
        ProviderContinuation? continuation = null)
    {
        try
        {
            if (option.Id == "youtube" && string.IsNullOrWhiteSpace(ReadCredential("youtube")))
            {
                var raw = await _ytDlp.SearchAsync(query, 16, cancellationToken);
                var mapped = await _core.SendAsync(new CoreRequest
                {
                    Action = "mapYTDLPSearch", Query = query, PageSize = 12,
                    ExternalToolOutputBase64 = Convert.ToBase64String(raw), Language = _settings.Current.Language
                }, cancellationToken: cancellationToken);
                option.Status = T("provider.bestEffort");
                return new ProviderBatch
                {
                    Provider = "youtube", DisplayName = "YouTube", Mode = "ytDLP",
                    State = new ProviderState { Availability = "bestEffort", Mode = "ytDLP" },
                    Assets = mapped.Assets ?? []
                };
            }
            var response = await _core.SendAsync(new CoreRequest
            {
                Action = "search", Query = query, MediaType = MediaType, Orientation = Orientation,
                Resolution = Resolution, Duration = Duration,
                YearFrom = int.TryParse(YearFrom, out var from) ? from : null,
                YearTo = int.TryParse(YearTo, out var to) ? to : null,
                DownloadableOnly = DownloadableOnly, PageSize = 20, ProviderIDs = [option.Id],
                Continuation = continuation,
                ApiKeys = CredentialDictionary(option.Id), Language = _settings.Current.Language
            }, cancellationToken: cancellationToken);
            var batch = response.ProviderBatches?.FirstOrDefault() ?? new ProviderBatch
            {
                Provider = option.Id, DisplayName = option.DisplayName,
                State = new ProviderState { Availability = "unavailable", Message = response.ErrorMessage }
            };
            option.Status = batch.State.Message ?? AvailabilityText(batch.State.Availability);
            option.Mode = ModeText(batch.Mode);
            return batch;
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception error)
        {
            option.Status = error.Message;
            return new ProviderBatch
            {
                Provider = option.Id, DisplayName = option.DisplayName,
                State = new ProviderState { Availability = "unavailable", Message = error.Message }
            };
        }
    }

    private async Task LoadMoreAsync()
    {
        if (_continuations.Count == 0 || string.IsNullOrWhiteSpace(_lastEffectiveQuery)) return;
        IsLoadingMore = true;
        var cancellationToken = _searchCancellation?.Token ?? CancellationToken.None;
        var targets = Providers.Where(option => option.Enabled && _continuations.ContainsKey(option.Id)).ToList();
        var tasks = targets.Select(async option =>
        {
            var continuation = _continuations[option.Id];
            var batch = await SearchProviderAsync(option, _lastEffectiveQuery, cancellationToken, continuation);
            return (Batch: batch, Previous: continuation);
        }).ToList();
        var seen = Results.Select(asset => asset.StableId).ToHashSet(StringComparer.OrdinalIgnoreCase);
        try
        {
            while (tasks.Count > 0)
            {
                var completed = await Task.WhenAny(tasks);
                tasks.Remove(completed);
                var result = await completed;
                var batch = result.Batch;
                if (batch.State.Availability == "unavailable")
                    _continuations[batch.Provider] = result.Previous;
                else if (batch.Continuation is not null) _continuations[batch.Provider] = batch.Continuation;
                else _continuations.Remove(batch.Provider);
                foreach (var asset in batch.Assets)
                    if (seen.Add(asset.StableId))
                    {
                        asset.PropertyChanged += ResultPropertyChanged;
                        Results.Add(asset);
                    }
                SearchStatus = _localization.Text("search.found", Results.Count);
            }
        }
        catch (OperationCanceledException) { SearchStatus = T("search.stopped"); }
        finally
        {
            IsLoadingMore = false;
            OnPropertyChanged(nameof(CanLoadMore));
            (LoadMoreCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
        }
    }

    private async Task ToggleFavoriteAsync(MediaAsset? asset)
    {
        if (asset is null) return;
        await _core.SendAsync(new CoreRequest
        {
            Action = "toggleFavorite", Asset = asset, ProjectID = CurrentProject?.Id.ToString(),
            Language = _settings.Current.Language
        });
        await LoadDatabaseAsync();
    }

    private void EnqueueDownload(MediaAsset? asset)
    {
        if (asset is null || !asset.Downloadable) return;
        if (DownloadRecords.Any(record =>
                record.StableAssetID.Equals(asset.StableId, StringComparison.OrdinalIgnoreCase) &&
                File.Exists(record.LocalPath)))
        {
            CurrentPage = "downloads";
            return;
        }
        Downloads.Enqueue(asset, CurrentProject?.Id, CurrentProject?.Name ?? T("common.uncategorized"));
        CurrentPage = "downloads";
    }

    private static MediaAsset? WithEditingOutput(MediaAsset? asset, string preset)
    {
        if (asset is null || asset.DownloadStrategy != "ytDLP") return asset;
        var metadata = new Dictionary<string, string>(asset.OriginalMetadata)
        {
            ["linkOutputPreset"] = preset,
            ["workflowVariantID"] = preset,
            ["linkMediaDuration"] = asset.Duration?.ToString(
                System.Globalization.CultureInfo.InvariantCulture) ?? "",
            ["linkAudioOnly"] = preset == "audioOnly" ? "true" : "false"
        };
        if (preset == "audioOnly")
            metadata["linkFormatSelector"] = "bestaudio[acodec!=none]/best";
        return asset.CloneForWorkflow(
            $"{asset.Id}:{preset}", metadata,
            preset == "audioOnly" ? "audio" : asset.MediaType,
            preset == "audioOnly" ? "m4a" :
                preset == "editingCompatibleMP4" ? "mp4" : asset.FileType);
    }

    private void ResultPropertyChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName != nameof(MediaAsset.IsSelected)) return;
        SelectedCount = Results.Count(asset => asset.IsSelected);
    }

    private void SelectAllVisible()
    {
        foreach (var asset in ResultsView.Cast<MediaAsset>()) asset.IsSelected = true;
    }

    private void ClearSelection()
    {
        foreach (var asset in Results) asset.IsSelected = false;
    }

    private void DownloadSelected()
    {
        var selected = Results.Where(asset => asset.IsSelected && asset.Downloadable).ToArray();
        foreach (var asset in selected)
            Downloads.Enqueue(asset, CurrentProject?.Id, CurrentProject?.Name ?? T("common.uncategorized"));
        if (selected.Length > 0) CurrentPage = "downloads";
    }

    private async Task AddSelectedToProjectAsync()
    {
        if (CurrentProject is null) return;
        foreach (var asset in Results.Where(asset => asset.IsSelected))
            await _core.SendAsync(new CoreRequest
            {
                Action = "addFavorite", Asset = asset, ProjectID = CurrentProject.Id.ToString(),
                Language = _settings.Current.Language
            });
        await LoadDatabaseAsync();
    }

    private async Task CreateProjectFromSelectionAsync()
    {
        if (string.IsNullOrWhiteSpace(NewProjectName) || SelectedCount == 0) return;
        await CreateProjectAsync();
        await AddSelectedToProjectAsync();
    }

    private async Task CopySelectedSourcesAsync()
    {
        var parts = new List<string>();
        foreach (var asset in Results.Where(asset => asset.IsSelected))
        {
            var response = await _core.SendAsync(new CoreRequest
            {
                Action = "formatSource", Asset = asset, Language = _settings.Current.Language
            });
            if (!string.IsNullOrWhiteSpace(response.Text)) parts.Add(response.Text);
        }
        if (parts.Count > 0) Clipboard.SetText(string.Join("\n\n---\n\n", parts));
    }

    private async Task CopyTextAsync(MediaAsset? asset, string action)
    {
        if (asset is null) return;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = action, Asset = asset, Language = _settings.Current.Language
        });
        if (!string.IsNullOrWhiteSpace(response.Text)) Clipboard.SetText(response.Text);
    }

    private async Task CreateProjectAsync()
    {
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "addProject", ProjectName = NewProjectName, Language = _settings.Current.Language
        });
        NewProjectName = "";
        ApplyDatabase(response.Database);
        CurrentProject = response.Project;
    }

    private async Task DeleteProjectAsync(ProjectRecord? project)
    {
        if (project is null) return;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "deleteProject", ProjectID = project.Id.ToString(), Language = _settings.Current.Language
        });
        if (CurrentProject?.Id == project.Id) CurrentProject = null;
        ApplyDatabase(response.Database);
    }

    private async Task SaveProjectAsync()
    {
        if (CurrentProject is null) return;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "updateProject", ProjectID = CurrentProject.Id.ToString(),
            ProjectName = ProjectEditName, ProjectScript = ScriptText,
            Language = _settings.Current.Language
        });
        ApplyDatabase(response.Database);
    }

    private async Task SearchHistoryAsync(SearchHistoryRecord? history)
    {
        if (history is null) return;
        Query = history.OriginalQuery;
        CurrentPage = "search";
        await SearchAsync();
    }

    private async Task ClearHistoryAsync()
    {
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "clearHistory", Language = _settings.Current.Language
        });
        ApplyDatabase(response.Database);
    }

    private async Task DeleteHistoryAsync(SearchHistoryRecord? history)
    {
        if (history is null) return;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "deleteHistory", RecordID = history.Id.ToString(),
            Language = _settings.Current.Language
        });
        ApplyDatabase(response.Database);
    }

    private async Task AnalyzeScriptAsync()
    {
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "splitScript", Query = ScriptText, Language = _settings.Current.Language
        });
        ScriptSegments.Clear();
        foreach (var segment in response.Segments ?? []) ScriptSegments.Add(segment);
    }

    private async Task OpenFeedbackAsync(string? destination)
    {
        if (string.IsNullOrWhiteSpace(destination)) return;
        try
        {
            var response = await _core.SendAsync(new CoreRequest
            {
                Action = "feedbackURL", FeedbackDestination = destination,
                Language = _settings.Current.Language
            });
            ShellService.OpenUrl(response.Text);
        }
        catch { }
    }

    private async Task AnalyzeLinksAsync()
    {
        var lines = LinkInput.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
            .Select(value => value.Trim()).Where(value => value.Length > 0).Take(25).ToArray();
        LinkItems.Clear();
        foreach (var line in lines) LinkItems.Add(new LinkDownloadItem(line));
        if (lines.Length == 0) { LinkStatus = T("link.invalidURL"); return; }
        IsLinkAnalyzing = true;
        LinkStatus = T("link.analyzing");
        using var limit = new SemaphoreSlim(2, 2);
        try
        {
            var tasks = LinkItems.Select(async item =>
            {
                if (!LinkUrlSafety.TryCreate(item.RawURL, out _))
                {
                    item.ErrorMessage = T("link.unsupportedURL"); item.IsSelected = false; return;
                }
                await limit.WaitAsync();
                try
                {
                    item.Analysis = await _ytDlp.AnalyzeAsync(item.RawURL, CancellationToken.None);
                    item.SelectedQuality = item.AvailableQualities.FirstOrDefault() ?? "best";
                    item.SubtitleLanguage = item.SubtitleLanguages.FirstOrDefault() ?? "";
                    item.ConfigureQualityLabels(QualityLabel);
                    item.ConfigureCreatorLabels(
                        value => T($"link.scope.{value}"), value => T($"link.output.{value}"),
                        value => T($"link.clip.{value}"));
                    item.InitializeClipEnd();
                }
                catch (Exception error)
                {
                    item.ErrorMessage = LinkErrorMessage(error); item.IsSelected = false;
                }
                finally { limit.Release(); }
            }).ToArray();
            await Task.WhenAll(tasks);
            LinkStatus = LinkItems.Any(item => item.IsReady) ? T("link.analysisComplete") : T("link.noneAnalyzed");
        }
        finally { IsLinkAnalyzing = false; }
    }

    private void DownloadLinkSelected()
    {
        var selected = LinkItems.Where(item => item.IsSelected && item.IsReady).ToArray();
        foreach (var item in selected)
        {
            var analysis = item.Analysis!;
            var selector = item.SelectedQuality switch
            {
                "p1080" => "bestvideo[height<=1080]+bestaudio/best[height<=1080]",
                "p720" => "bestvideo[height<=720]+bestaudio/best[height<=720]",
                "p480" => "bestvideo[height<=480]+bestaudio/best[height<=480]",
                "audioOnly" => "bestaudio[acodec!=none]/best",
                _ => "bestvideo+bestaudio/best"
            };
            if (item.OutputPreset == "audioOnly") selector = "bestaudio[acodec!=none]/best";
            var metadata = new Dictionary<string, string>
            {
                ["sourceName"] = analysis.SourceName, ["linkDownloader"] = "true",
                ["linkFormatSelector"] = selector, ["linkQuality"] = item.SelectedQuality,
                ["linkDownloadSubtitles"] = item.DownloadSubtitles ? "true" : "false",
                ["linkSubtitleLanguages"] = item.SubtitleLanguage,
                ["linkAudioOnly"] = item.OutputPreset == "audioOnly" || item.SelectedQuality == "audioOnly" ? "true" : "false",
                ["linkOutputPreset"] = item.OutputPreset,
                ["linkMediaDuration"] = analysis.Duration?.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? ""
            };
            if (item.SelectedScope == "clip")
            {
                metadata["linkClipStart"] = item.ClipStartSeconds?.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "";
                metadata["linkClipEnd"] = item.ClipEndSeconds?.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "";
                metadata["linkClipDuration"] = item.ClipDuration?.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "";
            }
            var audioOnly = item.OutputPreset == "audioOnly" || item.SelectedQuality == "audioOnly";
            var asset = new MediaAsset
            {
                Id = item.DownloadIdentity,
                Provider = "linkDownloader", Title = analysis.Title,
                ThumbnailURL = analysis.ThumbnailURL, SourcePageURL = analysis.OriginalURL,
                DownloadURL = analysis.OriginalURL, Creator = analysis.Creator,
                LicenseStatus = "UNKNOWN", Duration = analysis.Duration,
                Height = item.SelectedQuality switch { "p1080" => 1080, "p720" => 720, "p480" => 480, _ => null },
                FileType = audioOnly ? "m4a" : item.OutputPreset == "editingCompatibleMP4" ? "mp4" : "video",
                MediaType = audioOnly ? "audio" : "video",
                Downloadable = true, OriginalMetadata = metadata, SearchKeyword = analysis.OriginalURL,
                RelevanceScore = 1, DownloadStrategy = "ytDLP", DownloadAvailability = "conditional",
                RightsInfo = new RightsInfo { Source = analysis.SourceName, Known = false }
            };
            Downloads.Enqueue(asset, CurrentProject?.Id, CurrentProject?.Name ?? T("common.uncategorized"));
        }
        if (selected.Length > 0) CurrentPage = "downloads";
    }

    private List<string> LinkURLLines() => LinkInput.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
        .Select(value => value.Trim()).Where(value => LinkUrlSafety.TryCreate(value, out _))
        .Distinct(StringComparer.OrdinalIgnoreCase).ToList();

    private string LinkErrorMessage(Exception error) => error is ExternalToolException tool ? tool.Code switch
    {
        "unsupportedURL" => T("link.unsupportedURL"), "videoUnavailable" => T("link.mediaUnavailable"),
        "temporarilyBlocked" => T("link.signInRequired"), "regionalRestriction" => T("link.regionRestricted"),
        "rateLimited" => T("link.rateLimited"), "externalToolUnavailable" => T("link.toolUnavailable"),
        _ => T("link.downloadUnavailable")
    } : T("link.downloadUnavailable");

    private string QualityLabel(string value) => T($"link.quality.{value}");

    private async Task RemoveDownloadRecordAsync(DownloadRecord? record)
    {
        if (record is null) return;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "deleteDownload", RecordID = record.Id.ToString(),
            Language = _settings.Current.Language
        });
        ApplyDatabase(response.Database);
    }

    private async Task LoadDatabaseAsync()
    {
        try
        {
            var response = await _core.SendAsync(new CoreRequest
            {
                Action = "databaseSnapshot", Language = _settings.Current.Language
            });
            ApplyDatabase(response.Database);
        }
        catch { }
    }

    private void ApplyDatabase(PersistentDatabase? database)
    {
        if (database is null) return;
        Replace(Projects, database.Projects.OrderByDescending(x => x.UpdatedAt));
        Replace(Favorites, database.Favorites.OrderByDescending(x => x.SavedAt));
        Replace(History, database.History.OrderByDescending(x => x.SearchedAt));
        foreach (var record in database.Downloads) record.WorkflowSummary = DownloadWorkflowSummary(record);
        Replace(DownloadRecords, database.Downloads.OrderByDescending(x => x.DownloadedAt));
        if (CurrentProject is not null) CurrentProject = Projects.FirstOrDefault(x => x.Id == CurrentProject.Id);
    }

    private static void Replace<T>(ObservableCollection<T> target, IEnumerable<T> values)
    {
        target.Clear();
        foreach (var value in values) target.Add(value);
    }

    private bool MatchesProject(Guid? projectId) => CurrentProject is null || projectId == CurrentProject.Id;

    private bool MatchesFilters(MediaAsset asset)
    {
        if (MediaType != "all" && asset.MediaType != MediaType) return false;
        if (DownloadableOnly && !asset.IsDirectlyDownloadable) return false;
        if (Orientation != "all" && AssetOrientation(asset) != Orientation) return false;
        var minimumHeight = Resolution switch { "hd720" => 720, "fullHD" => 1080, "uhd4K" => 2160, _ => 0 };
        if (minimumHeight > 0 && Math.Min(asset.Width ?? 0, asset.Height ?? 0) < minimumHeight) return false;
        if (!DurationMatches(asset.Duration)) return false;
        if (int.TryParse(YearFrom, out var from) && (asset.PublishedDate?.Year ?? int.MinValue) < from) return false;
        if (int.TryParse(YearTo, out var to) && (asset.PublishedDate?.Year ?? int.MaxValue) > to) return false;
        return LicenseFilter switch
        {
            "knownOnly" => asset.RightsKnown,
            "openlyLicensed" => asset.RightsKnown && asset.OpenLicense,
            "publicDomain" => asset.RightsKnown && asset.PublicDomain,
            _ => true
        };
    }

    private bool DurationMatches(double? value) => Duration switch
    {
        "underMinute" => value is >= 0 and < 60,
        "oneToFive" => value is >= 60 and < 300,
        "fiveToTwenty" => value is >= 300 and < 1200,
        "overTwenty" => value is >= 1200,
        _ => true
    };

    private static string AssetOrientation(MediaAsset asset)
    {
        if (asset.Width is not > 0 || asset.Height is not > 0) return "unknown";
        var ratio = asset.Width.Value / (double)asset.Height.Value;
        if (ratio > 1.12) return "landscape";
        if (ratio < 0.88) return "portrait";
        return "square";
    }

    private static string Digits(string value) => new(value.Where(char.IsDigit).Take(4).ToArray());

    private void ApplySort()
    {
        ResultsView.SortDescriptions.Clear();
        var property = Sort switch
        {
            "newest" => nameof(MediaAsset.SortPublishedDate),
            "resolution" => nameof(MediaAsset.PixelCount),
            "duration" => nameof(MediaAsset.SortDuration),
            _ => nameof(MediaAsset.RelevanceScore)
        };
        ResultsView.SortDescriptions.Add(new SortDescription(property, ListSortDirection.Descending));
    }

    private Dictionary<string, string> CredentialDictionary(string provider)
    {
        var value = ReadCredential(provider);
        return string.IsNullOrWhiteSpace(value) ? [] : new Dictionary<string, string> { [provider] = value };
    }

    private string ReadCredential(string provider)
    {
        try { return _credentials.Read(provider); }
        catch { return ""; }
    }

    private void RefreshProviderModes()
    {
        foreach (var provider in Providers)
        {
            var hasKey = provider.SupportsApiKey && !string.IsNullOrWhiteSpace(ReadCredential(provider.Id));
            provider.Mode = hasKey
                ? $"{T("provider.mode.officialAPI")} · ✓ {T("settings.recommended")}" : provider.Id switch
            {
                "pexels" or "pixabay" => T("provider.mode.directSearch"),
                "youtube" => T("provider.mode.ytDLP"),
                "nasa" or "libraryOfCongress" or "peertube" or "openverse" or "dailymotion" => T("provider.mode.publicAPI"),
                "nationalArchives" or "europeana" or "videvo" or "videezy" or "mixkit" or "coverr" or "vimeo" => T("provider.mode.limited"),
                _ => T("provider.mode.publicInterface")
            };
            provider.Status = hasKey ? T("settings.configured") :
                provider.Id is "nationalArchives" or "europeana" or "videvo" or "videezy" or "mixkit" or "coverr" or "vimeo" ? T("provider.limitedMode") :
                provider.Id is "pexels" or "pixabay" or "youtube" ? T("provider.bestEffort") :
                provider.Id is "nasa" or "libraryOfCongress" or "peertube" or "openverse" or "dailymotion" ? T("provider.noKeyRequired") :
                T("provider.available");
            var values = provider.Id is "nationalArchives" or "europeana" or "videvo" or "videezy" or "mixkit" or "coverr" or "vimeo" && !hasKey
                ? new[] { T("provider.openOfficialSearch") }
                : new[] { T("capability.search"), T("capability.preview"), T("capability.metadata"),
                    T("capability.rights"), T("capability.download") };
            provider.Capabilities = _localization.Text("settings.capabilities", string.Join(" · ", values));
        }
    }

    private string AvailabilityText(string value) => value switch
    {
        "apiConnected" => T("provider.apiConnected"), "bestEffort" => T("provider.bestEffort"),
        "publicAPI" => T("provider.publicAPI"), "limitedMode" => T("provider.limitedMode"),
        "rateLimited" => T("provider.rateLimited"), "temporarilyBlocked" => T("provider.temporarilyBlocked"),
        "available" => T("provider.available"), _ => T("provider.unavailable")
    };

    private string ModeText(string value) => value switch
    {
        "officialAPI" => $"{T("provider.mode.officialAPI")} · ✓ {T("settings.recommended")}",
        "publicAPI" => T("provider.mode.publicAPI"), "limited" => T("provider.mode.limited"),
        "directSearch" => T("provider.mode.directSearch"),
        "ytDLP" => T("provider.mode.ytDLP"), _ => T("provider.mode.publicInterface")
    };

    private void RefreshLanguage()
    {
        OnPropertyChanged(null);
        foreach (var item in LinkItems)
        {
            item.ConfigureQualityLabels(QualityLabel);
            item.ConfigureCreatorLabels(
                value => T($"link.scope.{value}"), value => T($"link.output.{value}"),
                value => T($"link.clip.{value}"));
        }
        RefreshProviderModes();
        Downloads.RefreshLocalizedStatus();
        foreach (var record in DownloadRecords) record.WorkflowSummary = DownloadWorkflowSummary(record);
        DownloadRecordsView.Refresh();
        SearchStatus = T("search.initialStatus");
    }

    private string DownloadWorkflowSummary(DownloadRecord record)
    {
        if (string.IsNullOrWhiteSpace(record.OutputPresetRaw)) return "";
        var values = new List<string>
        {
            $"{T("link.outputFormat")}: {T($"link.output.{record.OutputPresetRaw}")}"
        };
        if (record.ClipStartSeconds is { } start && record.ClipEndSeconds is { } end)
        {
            values.Add($"{T("link.clip.start")}: {Timecode(start)}");
            values.Add($"{T("link.clip.end")}: {Timecode(end)}");
            if (record.ClipDurationSeconds is { } duration)
                values.Add(_localization.Text("link.clip.duration", Timecode(duration)));
        }
        return string.Join(" · ", values);
    }

    private static string Timecode(double seconds) =>
        TimeSpan.FromSeconds(Math.Max(0, Math.Floor(seconds))).ToString(@"hh\:mm\:ss");
}
