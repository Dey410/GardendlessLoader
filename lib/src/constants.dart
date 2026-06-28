const appDisplayName = 'GardendlessLoader'; // App 显示名称
const appBundleId =
    'io.github.dey410.gardendlessloader'; // App 包名（Bundle ID），用于区分不同平台的应用
const githubUrl =
    'https://github.com/Gzh0821/pvzge_web'; // GitHub 仓库地址，指向 PvZ2 Gardendless 项目的源代码
const appGithubUrl =
    'https://github.com/Dey410/GardendlessLoader'; // GardendlessLoader 的 GitHub 仓库地址
const bilibiliHomeUrl = 'https://space.bilibili.com/523667580'; // B站主页地址
const remoteAnnouncementUrl =
    'https://raw.githubusercontent.com/Dey410/GardendlessLoader/main/announcements.json'; // 远程公告 URL
const remoteAboutContentUrl =
    'https://raw.githubusercontent.com/Dey410/GardendlessLoader/main/about_content.json'; // 远程关于内容 URL
const resourceFolderName = 'GardendlessLoader'; // 资源文件夹名称
const localServerHost = '127.0.0.1'; // 本地服务器地址，通常使用 localhost 或 127.0.0.1
const localServerPort = 26410; // (彩蛋)其实这是小朱20岁生日的数字，哈哈哈,看见的可以发评论区告诉我哦~
const localOrigin = 'http://$localServerHost:$localServerPort';
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.4.4');
const announcementTimeout = Duration(seconds: 3); //公告请求超时时间
const announcementMaxBytes = 32 * 1024; //公告请求最大响应体大小，32KB应该足够了
const aboutContentTimeout = Duration(seconds: 3); //关于内容请求超时时间
const aboutContentMaxBytes = 16 * 1024; //关于内容请求最大响应体大小
