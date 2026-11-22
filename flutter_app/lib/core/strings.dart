class AppStrings {
  const AppStrings({this.english = false});
  final bool english;
  String text(String key) {
    final pair = _strings[key];
    if (pair == null) {
      throw ArgumentError.value(key, 'key', 'Missing translation');
    }
    return pair[english ? 1 : 0];
  }

  static const _strings = <String, List<String>>{
    'welcome': ['让知识，随时在手', 'Your knowledge, always with you'],
    'welcomeHint': [
      '连接你的 BookStark，继续阅读与记录',
      'Connect to BookStark. Keep reading and creating.',
    ],
    'serverSpace': ['服务器空间', 'Server'],
    'localSpace': ['本地空间', 'Local'],
    'server': ['服务器地址', 'Server address'],
    'account': ['账号', 'Account'],
    'password': ['密码', 'Password'],
    'enterAccount': ['请输入账号', 'Enter your account'],
    'enterPassword': ['请输入密码', 'Enter your password'],
    'showPassword': ['显示密码', 'Show password'],
    'hidePassword': ['隐藏密码', 'Hide password'],
    'forgot': ['忘记密码？', 'Forgot password?'],
    'connect': ['连接并登录', 'Connect and sign in'],
    'connecting': ['正在连接…', 'Connecting…'],
    'register': ['注册', 'Register'],
    'noAccount': ['还没有账号？', 'New to BookStark?'],
    'localHint': [
      '本地空间无需登录，可离线记录',
      'No sign-in needed for your offline local space',
    ],
    'openLocal': ['进入本地空间', 'Open local space'],
    'localDescription': [
      '笔记和阅读资料保存在此设备。AI 和在线语音需要联网。',
      'Notes and reading material stay on this device. AI and online speech require a connection.',
    ],
    'required': ['请填写此项', 'This field is required'],
    'invalidServer': [
      '请输入有效的 HTTP/HTTPS 服务器地址',
      'Enter a valid HTTP/HTTPS server address',
    ],
    'connectionFailed': [
      '连接失败，请检查网络和服务器地址',
      'Connection failed. Check your network and server address.',
    ],
    'home': ['首页', 'Home'],
    'knowledge': ['知识', 'Knowledge'],
    'favorites': ['收藏', 'Saved'],
    'files': ['文件', 'Files'],
    'me': ['我的', 'Me'],
    'search': ['全局搜索', 'Global search'],
    'journey': ['继续你的知识旅程', 'Continue your knowledge journey'],
    'journeyHint': [
      '阅读、记录、整理，从这里开始',
      'Read, write and organize, all in one place',
    ],
    'recent': ['最近更新', 'Recently updated'],
    'shortcuts': ['快捷入口', 'Quick access'],
    'articles': ['文章', 'Articles'],
    'notes': ['笔记', 'Notes'],
    'books': ['书籍', 'Books'],
    'tasks': ['待办', 'Tasks'],
    'bookmarks': ['书签', 'Bookmarks'],
    'nav': ['导航', 'Navigation'],
    'topics': ['主题', 'Topics'],
    'labels': ['标签管理', 'Labels'],
    'images': ['图片库', 'Images'],
    'trash': ['回收站', 'Trash'],
    'public-feed': ['公开广场', 'Public feed'],
    'public-notes': ['公开笔记', 'Public notes'],
    'create-resource': ['新建资源', 'Create resource'],
    'assistant': ['打开 AI 助手', 'Open AI assistant'],
    'retry': ['重试', 'Retry'],
    'nothingRecent': ['还没有最近记录', 'No recent items yet'],
    'signOut': ['退出登录', 'Sign out'],
    'back': ['返回', 'Back'],
    'registerTitle': ['创建你的账号', 'Create your account'],
    'registerHint': [
      '填写账号信息，提交注册申请',
      'Enter your details to request an account',
    ],
    'email': ['邮箱', 'Email'],
    'confirm': ['确认密码', 'Confirm password'],
    'invite': ['邀请码', 'Invitation code'],
    'inviteOptional': ['填写邀请码（可选）', 'Add an invitation code (optional)'],
    'inviteRequired': ['请输入邀请码', 'An invitation code is required'],
    'createAccount': ['创建账号', 'Create account'],
    'registerNote': [
      '如服务器开启审批，注册后需等待管理员确认',
      'Your server may require administrator approval after registration',
    ],
    'alreadyAccount': ['已有账号？', 'Already have an account?'],
    'backLogin': ['返回登录', 'Back to sign in'],
    'forgotTitle': ['找回你的账号', 'Recover your account'],
    'forgotHint': [
      '输入账号或注册邮箱，我们将发送重置链接',
      'Enter your account or registered email to request a reset link',
    ],
    'identity': ['账号或邮箱', 'Account or email'],
    'sendReset': ['发送重置邮件', 'Send reset email'],
    'resetNotice': [
      '如果账号存在，重置邮件将发送到注册邮箱',
      'If the account exists, a reset email will be sent to its registered address',
    ],
    'resetCheckMail': [
      '未收到邮件？检查垃圾邮件，或稍后重试',
      'Check your spam folder, or try again later',
    ],
    'haveResetLink': [
      '已有重置链接？ 设置新密码',
      'Already have a reset link? Set a new password',
    ],
    'reset': ['设置新密码', 'Set new password'],
    'resetTitle': ['设置新密码', 'Set a new password'],
    'resetHint': [
      '输入邮件中的重置链接，并设置新密码',
      'Paste the reset link from your email and choose a new password',
    ],
    'token': ['重置链接或令牌', 'Reset link or token'],
    'newPassword': ['新密码', 'New password'],
    'savePassword': ['保存新密码', 'Save new password'],
    'resetOnce': [
      '重置链接只能使用一次；失效后请重新申请',
      'Reset links can only be used once. Request a new link if it has expired',
    ],
    'passwordShort': ['密码至少 6 个字符', 'Use at least 6 characters'],
    'passwordMismatch': ['两次密码不一致', 'Passwords do not match'],
    'invalidEmail': ['请输入有效邮箱', 'Enter a valid email address'],
    'wrongResetServer': [
      '重置链接与服务器地址不匹配',
      'The reset link does not belong to this server',
    ],
    'invalidResetLink': [
      '重置链接中没有令牌',
      'The reset link does not contain a token',
    ],
    'registerSuccess': [
      '注册成功，请按服务器提示等待审批或返回登录',
      'Registration complete. Follow your server’s approval instructions, then sign in',
    ],
    'resetSuccess': ['密码已重置，请返回登录', 'Password reset. You can now sign in'],
    'authLoginRejectedTitle': ['登录未成功', 'Sign-in was not successful'],
    'authBadCredentials': [
      '账号或密码不正确，请检查后重试。',
      'Account or password is incorrect. Check and retry.',
    ],
    'authApprovalRequired': [
      '账号尚未通过审批，请联系管理员。',
      'Account approval is required. Contact your administrator.',
    ],
    'authRateTitle': ['请求过于频繁', 'Too many requests'],
    'authRateBody': ['请稍后再试。', 'Please try again later.'],
    'authMailUnavailableTitle': ['暂时无法发送邮件', 'Email could not be sent'],
    'authMailUnavailableBody': [
      '服务器尚未启用找回密码，请联系管理员。',
      'Server password recovery is not enabled. Contact your administrator.',
    ],
    'authResetInvalidTitle': [
      '链接无效或已过期',
      'The reset link is invalid or expired',
    ],
    'authResetInvalidBody': [
      '请返回登录页重新申请重置邮件。',
      'Return to sign-in to request a new reset email.',
    ],
    'authRegistrationRejected': ['注册未成功', 'Registration was not successful'],
    'authDuplicateRegistration': [
      '账号或邮箱可能已存在，请更换或返回登录。',
      'The account or email may already exist. Choose another or return to sign-in.',
    ],
    'authInviteRejected': [
      '请检查邀请码后重试。',
      'Check the invitation code and retry.',
    ],
    'authRequestRejectedTitle': ['请求未被接受', 'Request was not accepted'],
    'authRequestRejectedBody': [
      '请检查填写内容后重试。',
      'Check the entered details and retry.',
    ],
    'passwordLong': [
      '密码过长，请缩短后重试。',
      'The password is too long. Shorten it and retry.',
    ],
    'authServiceUnavailableTitle': [
      '服务暂不可用',
      'Service temporarily unavailable',
    ],
    'authServiceUnavailableBody': [
      '服务器暂时无法处理请求，请稍后重试。',
      'The server cannot process this request right now. Try again later.',
    ],
    'authUnconfirmedTitle': ['结果尚未确认', 'The result could not be confirmed'],
    'authRegistrationUnconfirmed': [
      '注册可能已提交，请先返回登录核对。',
      'Registration may have been submitted. Return to sign-in to check first.',
    ],
    'authResetUnconfirmed': [
      '密码可能已更新，请先返回登录，使用新密码核对。',
      'The password may have changed. Return to sign-in and try the new password first.',
    ],
    'authMailUnconfirmedTitle': ['发送结果尚未确认', 'Delivery could not be confirmed'],
    'authMailUnconfirmedBody': [
      '请先检查收件箱，稍后再尝试发送。',
      'Check your inbox before trying to send again.',
    ],
    'authConnectionFailedTitle': ['连接失败', 'Connection failed'],
    'authRegistrationPendingTitle': ['注册申请已提交', 'Registration submitted'],
    'authRegistrationPendingBody': [
      '请等待管理员审批后再登录。',
      'Wait for administrator approval before signing in.',
    ],
    'authRegistrationApprovedTitle': ['注册成功', 'Registration complete'],
    'authRegistrationApprovedBody': [
      '现在可以返回登录。',
      'You can now return to sign-in.',
    ],
    'authRegistrationSubmittedTitle': ['注册已提交', 'Registration submitted'],
    'authResetCompleteTitle': ['密码已重置', 'Password reset'],
    'authMailRequestedTitle': ['重置请求已提交', 'Reset requested'],
    'authRetrySending': ['重试发送', 'Retry sending'],
    'authVerifyLogin': ['返回登录核对', 'Return to sign-in to check'],
    'showConfirmPassword': ['显示确认密码', 'Show confirmation password'],
    'hideConfirmPassword': ['隐藏确认密码', 'Hide confirmation password'],
    'authWelcomeTitle': ['连接你的知识库', 'Connect your knowledge library'],
    'authRepeatPassword': ['请再次输入密码', 'Repeat your password'],
    'authPasteResetLink': ['输入重置链接或令牌', 'Paste the reset link or token'],
    'authInputTooLong': [
      '填写内容过长，请缩短后重试。',
      'The entered details are too long. Shorten them and retry.',
    ],
    'authRegisterBarTitle': ['注册账号', 'Register'],
    'authForgotBarTitle': ['找回密码', 'Recover password'],
    'authResetBarTitle': ['重置密码', 'Reset password'],
    'authForgotLink': ['忘记密码', 'Forgot password'],
    'submitting': ['正在提交…', 'Submitting…'],
  };
}
